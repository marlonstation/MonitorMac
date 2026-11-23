#include "../Sources/Sensors.h"
#include <stdio.h>
int main(){MMSensor s[512];int n=mm_read_smc(s,512);printf("SMC count: %d\n",n);for(int i=0;i<n;i++)printf("%s\t%.2f °C\n",s[i].name,s[i].celsius);return n<0;}
