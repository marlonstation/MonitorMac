#include "../Sources/Sensors.h"
#include <stdio.h>
int main(){MMSensor s[256];int n=mm_read_sensors(s,256);for(int i=0;i<n;i++)printf("%s\t%.2f °C\n",s[i].name,s[i].celsius);return n<0;}
