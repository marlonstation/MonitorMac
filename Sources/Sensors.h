#ifndef MONITORMAC_SENSORS_H
#define MONITORMAC_SENSORS_H
#include <stdint.h>
typedef struct { char name[128]; double celsius; } MMSensor;
int mm_read_sensors(MMSensor *output, int capacity);
int mm_read_smc(MMSensor *output, int capacity);
void mm_reset_smc_cache(void);
const char *mm_smc_message(void);
double mm_smc_decode(uint32_t type,const unsigned char *bytes,unsigned size);
#endif
