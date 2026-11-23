#include "../Sources/Sensors.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 unsigned char fixed[]={0x2c,0x80};assert(mm_smc_decode(0x73703738,fixed,2)==44.5);
 unsigned char negative[]={0xff,0x80};assert(mm_smc_decode(0x73703738,negative,2)==-0.5);
 float sample=42.25f;assert(mm_smc_decode(0x666c7420,(unsigned char*)&sample,4)==42.25);
 assert(isnan(mm_smc_decode(0x666c7420,fixed,2)));
 assert(isnan(mm_smc_decode(0,NULL,0)));
 assert(isnan(mm_smc_decode(0x78787878,fixed,2)));
 puts("PASS: SMC ABI and decoding (float, sp78, invalid input)");
}
