mkdir -p firmware/bad-idf
printf 'idf_component_register(SRCS "main.c")\n' > firmware/bad-fw/CMakeLists.txt
cat > firmware/bad-fw/identity.c <<'INNER'
static const char *IDENTITY =
	"{\"deviceId\":\"gaia-x\",\"kind\":\"gaia-sensor\",\"protocol\":\"hermes/1\"}";
static const char *TOPIC = "olympia/v2/devices/gaia-x/telemetry";
INNER
printf '#!/bin/sh\nesptool.py write_flash 0x0 app.bin\n' > firmware/bad-fw/flash.sh
printf 'CONFIG_ESP_WIFI_PASSWORD="hunter2"\n' > firmware/bad-idf/sdkconfig.defaults
printf 'nvs,data,nvs,0x9000,24K,\nfactory,app,factory,0x10000,1M,\n' > firmware/bad-idf/partitions.csv
