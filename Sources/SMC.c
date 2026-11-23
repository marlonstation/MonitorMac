#include "Sensors.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_error.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stddef.h>
#include <time.h>

// Read-only SMC protocol. No key write command is implemented.
typedef struct {uint8_t major,minor,build,reserved;uint16_t release;} Version;
typedef struct {uint16_t version,length;uint32_t cpuPLimit,gpuPLimit,memPLimit;} PLimit;
typedef struct {uint32_t size,type;uint8_t attributes;} KeyInfo;
typedef struct {uint32_t key;Version vers;PLimit limit;KeyInfo info;uint8_t result,status,command;uint32_t data;uint8_t bytes[32];} Packet;
_Static_assert(sizeof(Packet)==80,"SMC ABI must be 80 bytes");
_Static_assert(offsetof(Packet,result)==40,"SMC result offset");
_Static_assert(offsetof(Packet,bytes)==48,"SMC data offset");

typedef struct {uint32_t key;KeyInfo info;unsigned missed;int hadValue;} CachedKey;
// Called only from the serial sampling queue, or from a single-threaded diagnostic.
static CachedKey cached[512];
static int cachedCount=0;
static unsigned failures=0;
static double lastDiscovery=0;
static double monotonicSeconds(void){struct timespec now;if(clock_gettime(CLOCK_MONOTONIC,&now)!=0)return 0;return now.tv_sec+now.tv_nsec/1e9;}
void mm_reset_smc_cache(void){cachedCount=0;failures=0;lastDiscovery=0;}
static char diagnostic[256]="SMC not queried yet";
const char *mm_smc_message(void){return diagnostic;}
static uint32_t code(const char *s){return ((uint32_t)(uint8_t)s[0]<<24)|((uint32_t)(uint8_t)s[1]<<16)|((uint32_t)(uint8_t)s[2]<<8)|(uint8_t)s[3];}
static void nameForKey(uint32_t key,char name[5]){name[0]=key>>24;name[1]=key>>16;name[2]=key>>8;name[3]=key;name[4]=0;}
static int call(io_connect_t c,Packet *in,Packet *out){
 size_t n=sizeof(*out);memset(out,0,n);
 kern_return_t kr=IOConnectCallStructMethod(c,2,in,sizeof(*in),out,&n);
 if(kr!=KERN_SUCCESS){snprintf(diagnostic,sizeof(diagnostic),"SMC: call failed 0x%08x (%s)",kr,mach_error_string(kr));return 0;}
 if(n!=sizeof(*out)||out->result!=0){snprintf(diagnostic,sizeof(diagnostic),"SMC: invalid response, size %zu, result 0x%02x",n,out->result);return 0;}
 return 1;
}
static int infoForKey(io_connect_t c,uint32_t key,KeyInfo *info){Packet in={0},out;in.key=key;in.command=9;if(!call(c,&in,&out))return 0;*info=out.info;return info->size>0&&info->size<=32;}
static int bytesForKey(io_connect_t c,uint32_t key,KeyInfo info,Packet *out){Packet in={0};in.key=key;in.command=5;in.info.size=info.size;return call(c,&in,out);}

double mm_smc_decode(uint32_t type,const unsigned char *bytes,unsigned size){
 if(!bytes)return NAN;
 if(type==code("flt ")&&size==4){float f;memcpy(&f,bytes,4);return (double)f;}
 if(type==code("sp78")&&size==2){int16_t raw=(int16_t)((bytes[0]<<8)|bytes[1]);return raw/256.0;}
 if(type==code("fpe2")&&size==2)return ((bytes[0]<<8)|bytes[1])/4.0;
 if(type==code("ui16")&&size==2)return (bytes[0]<<8)|bytes[1];
 return NAN;
}
int mm_read_smc(MMSensor *out,int cap){
 if(!out||cap<=0)return 0;
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if(!service){snprintf(diagnostic,sizeof(diagnostic),"SMC: AppleSMC service not found");return -1;}
 io_connect_t connection=0;
 kern_return_t kr=IOServiceOpen(service,mach_task_self(),0,&connection);IOObjectRelease(service);
 if(kr!=KERN_SUCCESS){
  snprintf(diagnostic,sizeof(diagnostic),"SMC: IOServiceOpen 0x%08x (%s). This execution context may restrict access.",kr,mach_error_string(kr));return -1;
 }
 if(!cachedCount){
  lastDiscovery=monotonicSeconds();
  KeyInfo info;Packet n;
  if(!infoForKey(connection,code("#KEY"),&info)||!bytesForKey(connection,code("#KEY"),info,&n)){
   IOServiceClose(connection);return -2;
  }
  unsigned total=((unsigned)n.bytes[0]<<24)|((unsigned)n.bytes[1]<<16)|((unsigned)n.bytes[2]<<8)|n.bytes[3];
  if(total>20000)total=20000;
  for(unsigned i=0;i<total&&cachedCount<512;i++){
   Packet in={0},key;in.command=8;in.data=i;if(!call(connection,&in,&key))continue;
   char name[5];nameForKey(key.key,name);
   if(name[0]!='T'||!infoForKey(connection,key.key,&info))continue;
   if(info.type!=code("flt ")&&info.type!=code("sp78")&&info.type!=code("fpe2")&&info.type!=code("ui16"))continue;
   cached[cachedCount++]=(CachedKey){.key=key.key,.info=info};
  }
 }
 int count=0,partialFailure=0;
 for(int i=0;i<cachedCount&&count<cap;i++){
  Packet value;double t=NAN;
  if(bytesForKey(connection,cached[i].key,cached[i].info,&value))t=mm_smc_decode(cached[i].info.type,value.bytes,cached[i].info.size);
  if(isfinite(t)&&t>0&&t<150){char name[5];nameForKey(cached[i].key,name);snprintf(out[count].name,128,"SMC %s",name);out[count++].celsius=t;cached[i].hadValue=1;cached[i].missed=0;}
  else if(cached[i].hadValue){if(cached[i].missed<3)cached[i].missed++;if(cached[i].missed>=3)partialFailure=1;}
 }
 IOServiceClose(connection);
 if(count){failures=0;snprintf(diagnostic,sizeof(diagnostic),"SMC: %d valid temperatures, %d cached keys",count,cachedCount);}
 else if(++failures>=3){cachedCount=0;failures=0;}
 if(!count&&!cachedCount)snprintf(diagnostic,sizeof(diagnostic),"SMC: connection open, no readable temperature keys");
 // Recover disappearing sensors even while others still work; rate-limit
 // rediscovery so an intermittent key cannot cause continuous enumeration.
 if(partialFailure&&monotonicSeconds()-lastDiscovery>=30){cachedCount=0;snprintf(diagnostic,sizeof(diagnostic),"SMC: %d valid temperatures; refreshing sensor discovery after partial failure",count);}
 return count;
}
