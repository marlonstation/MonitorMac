#include "Sensors.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
// Runtime loading: temperature events are not a stable public macOS API.
int mm_read_sensors(MMSensor *out, int cap) {
 void *lib=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
 if (!lib) return -1;
 CFTypeRef (*create)(CFAllocatorRef)=dlsym(lib,"IOHIDEventSystemClientCreate");
 void (*matching)(CFTypeRef,CFDictionaryRef)=dlsym(lib,"IOHIDEventSystemClientSetMatching");
 CFArrayRef (*services)(CFTypeRef)=dlsym(lib,"IOHIDEventSystemClientCopyServices");
 CFTypeRef (*property)(CFTypeRef,CFStringRef)=dlsym(lib,"IOHIDServiceClientCopyProperty");
 CFTypeRef (*event)(CFTypeRef,int,int64_t,int)=dlsym(lib,"IOHIDServiceClientCopyEvent");
 double (*value)(CFTypeRef,int)=dlsym(lib,"IOHIDEventGetFloatValue");
 if(!create||!matching||!services||!property||!event||!value){dlclose(lib);return -1;}
 CFTypeRef client=create(kCFAllocatorDefault);
 if(!client){dlclose(lib);return -1;}
 int page=0xff00, usage=5;
 CFNumberRef p=CFNumberCreate(NULL,kCFNumberIntType,&page),u=CFNumberCreate(NULL,kCFNumberIntType,&usage);
 const void *keys[]={CFSTR("PrimaryUsagePage"),CFSTR("PrimaryUsage")};
 const void *vals[]={p,u};
 CFDictionaryRef match=CFDictionaryCreate(NULL,keys,vals,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 matching(client,match); CFRelease(match);CFRelease(p);CFRelease(u);
 CFArrayRef list=services(client); int count=0;
 if(list){for(CFIndex i=0;i<CFArrayGetCount(list)&&count<cap;i++){
  CFTypeRef service=CFArrayGetValueAtIndex(list,i);
  CFTypeRef name=property(service,CFSTR("Product"));
  CFTypeRef e=event(service,15,0,0);
  if(name&&CFGetTypeID(name)==CFStringGetTypeID()&&e){
   double t=value(e,15<<16);
   if(isfinite(t)&&t>0&&t<150&&CFStringGetCString(name,out[count].name,128,kCFStringEncodingUTF8)){out[count].celsius=t;count++;}
  }
  if(e)CFRelease(e);if(name)CFRelease(name);
 }CFRelease(list);}
 CFRelease(client);dlclose(lib);return count;
}
