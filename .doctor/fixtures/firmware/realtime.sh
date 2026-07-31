cat > firmware/bad-fw/bad.cpp <<'INNER'
#define LED_PIN 2
#define SENSOR_GPIO 14
int sampleCount = 0;
volatile int tickFlag = 0;

void IRAM_ATTR onTick() {
	double ratio = 1.5;
	Serial.println(ratio);
	sampleCount++;
	tickFlag = 1;
	int a1 = 1;
	int a2 = 2;
	int a3 = 3;
	int a4 = 4;
	int a5 = 5;
	int a6 = 6;
	int a7 = 7;
	int a8 = 8;
	int a9 = 9;
	int a10 = 10;
	int a11 = 11;
	int a12 = 12;
	int a13 = 13;
	int a14 = 14;
	int a15 = 15;
	int a16 = 16;
	int a17 = 17;
	int a18 = 18;
	int a19 = 19;
	int a20 = 20;
}

void setup() {
	pinMode(4, OUTPUT);
	digitalWrite(4, 1);
	attachInterrupt(digitalPinToInterrupt(5), onTick, RISING);
	WiFi.begin(ssid, pass);
	while (WiFi.status() != WL_CONNECTED) {
		delay(500);
	}
	xTaskCreate(worker, "worker", 4096, NULL, 5, NULL);
}
INNER
