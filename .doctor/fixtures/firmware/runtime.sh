mkdir -p firmware/bad-loop
cat > firmware/bad-loop/main.cpp <<'INNER'
#define MQTT_BROKER_HOST "192.168.1.42"

static char buffer[64];

String label(int value) {
	return String(value);
}

void provision() {
	mbedtls_rsa_gen_key(&ctx, rng, NULL, 2048, 65537);
}

void setup() {
	Serial.begin(9600);
	nvs_flash_init();
}

void loop() {
	char *scratch = (char *) malloc(64);
	Serial.printf("tick %d\n", 1);
	delay(100);
	free(scratch);
}

void worker(void *arg) {
	for (;;) {
		readSensor();
	}
}
INNER
