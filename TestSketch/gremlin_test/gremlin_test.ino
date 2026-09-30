// gremlin_test — exercises Gremlin's serial monitor, plotter, and send field.
//
// Streams plottable data and periodic log lines. Type `help` in the send field
// for commands that trigger specific cases (bursts, gaps, malformed lines, ...).
// Written for Teensy 4.1 but uses only core Arduino APIs.

#include <math.h>

// ---- Configuration ----------------------------------------------------------

const unsigned long BAUD_RATE = 115200;          // ignored by Teensy USB serial
const unsigned long SERIAL_WAIT_MS = 3000;       // wait this long for the monitor at boot
const unsigned long HEARTBEAT_INTERVAL_MS = 5000;
const unsigned long SLOW_SENSOR_INTERVAL_MS = 2000;
const unsigned int DEFAULT_RATE_HZ = 20;
const unsigned int MAX_RATE_HZ = 2000;
const unsigned int MAX_BURST_LINES = 5000;
const unsigned int LONG_LINE_LENGTH = 300;
const size_t COMMAND_BUFFER_SIZE = 128;
const float WAVE_PERIOD_S = 4.0;
const int RAMP_MAX = 100;

// ---- State ------------------------------------------------------------------

unsigned int rateHz = DEFAULT_RATE_HZ;
bool streaming = true;
bool gapMode = false;      // drop "cosine" from every other sample
bool slowSensor = false;   // emit a separate temp: line every 2 s
bool ledOn = false;

unsigned long sampleCount = 0;
unsigned long lastSampleUs = 0;
unsigned long lastHeartbeatMs = 0;
unsigned long lastSlowSensorMs = 0;
int ramp = 0;

char command[COMMAND_BUFFER_SIZE];
size_t commandLength = 0;

// ---- Setup / loop -----------------------------------------------------------

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(BAUD_RATE);
  while (!Serial && millis() < SERIAL_WAIT_MS) {
    // Teensy: wait briefly for the host to open the port so the banner isn't lost
  }

  Serial.println("gremlin_test ready.");
  Serial.println("INFO:type 'help' for commands");
  printStatus();
}

void loop() {
  readCommands();

  unsigned long nowUs = micros();
  if (streaming && nowUs - lastSampleUs >= 1000000UL / rateHz) {
    lastSampleUs = nowUs;
    sendSample(nowUs);
  }

  unsigned long nowMs = millis();
  if (streaming && slowSensor && nowMs - lastSlowSensorMs >= SLOW_SENSOR_INTERVAL_MS) {
    lastSlowSensorMs = nowMs;
    Serial.print("temp:");
    Serial.println(22.0 + (nowMs % 1000) / 1000.0, 2);
  }

  if (nowMs - lastHeartbeatMs >= HEARTBEAT_INTERVAL_MS) {
    lastHeartbeatMs = nowMs;
    Serial.print("DEBUG:uptime ");
    Serial.print(nowMs / 1000);
    Serial.print("s, samples ");
    Serial.println(sampleCount);
  }
}

// ---- Data -------------------------------------------------------------------

// One data line: sine and cosine (floats, negative values), ramp (integer sawtooth).
void sendSample(unsigned long nowUs) {
  float t = nowUs / 1000000.0;
  float phase = 2.0 * M_PI * t / WAVE_PERIOD_S;
  sampleCount++;
  ramp = (ramp + 1) % (RAMP_MAX + 1);

  Serial.print("sine:");
  Serial.print(sin(phase), 3);
  if (!(gapMode && sampleCount % 2 == 0)) {
    Serial.print(",cosine:");
    Serial.print(cos(phase), 3);
  }
  Serial.print(",ramp:");
  Serial.println(ramp);
}

// ---- Commands -----------------------------------------------------------------

// Collects characters until newline; handles several commands in one send.
void readCommands() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      command[commandLength] = '\0';
      if (commandLength > 0) handleCommand(command);
      commandLength = 0;
    } else if (commandLength < COMMAND_BUFFER_SIZE - 1) {
      command[commandLength++] = c;
    }
  }
}

void handleCommand(const char *input) {
  String line = String(input);
  line.trim();
  int space = line.indexOf(' ');
  String name = space < 0 ? line : line.substring(0, space);
  String arg = space < 0 ? String("") : line.substring(space + 1);
  name.toLowerCase();

  if (name == "help") {
    printHelp();
  } else if (name == "ping") {
    Serial.println("pong");
  } else if (name == "echo") {
    Serial.print("echo: ");
    Serial.println(arg);
  } else if (name == "status") {
    printStatus();
  } else if (name == "pause") {
    streaming = false;
    Serial.println("INFO:data paused");
  } else if (name == "resume") {
    streaming = true;
    Serial.println("INFO:data resumed");
  } else if (name == "rate") {
    setRate(arg.toInt());
  } else if (name == "gap") {
    gapMode = !gapMode;
    Serial.println(gapMode ? "INFO:gap mode on (cosine every other sample)" : "INFO:gap mode off");
  } else if (name == "slow") {
    slowSensor = !slowSensor;
    Serial.println(slowSensor ? "INFO:slow temp sensor on" : "INFO:slow temp sensor off");
  } else if (name == "levels") {
    printLevels();
  } else if (name == "burst") {
    burst(arg.length() > 0 ? arg.toInt() : 600);
  } else if (name == "malformed") {
    printMalformed();
  } else if (name == "long") {
    printLongLine();
  } else if (name == "utf8") {
    Serial.println("UTF-8: café, 温度, ✓ — plain log");
  } else if (name == "partial") {
    printPartialLine();
  } else if (name == "blank") {
    Serial.println();
    Serial.println("   ");
    Serial.println("INFO:two blank lines above");
  } else if (name == "led") {
    setLed(arg);
  } else {
    Serial.print("WARN:unknown command '");
    Serial.print(line);
    Serial.println("' - type help");
  }
}

void printHelp() {
  Serial.println("Commands:");
  Serial.println("  help            this list");
  Serial.println("  ping            replies pong");
  Serial.println("  echo <text>     echoes text back");
  Serial.println("  status          current settings");
  Serial.println("  pause | resume  stop/start the data stream");
  Serial.println("  rate <hz>       samples per second (1-2000)");
  Serial.println("  gap             toggle gaps in the cosine trace");
  Serial.println("  slow            toggle a separate temp: line every 2 s");
  Serial.println("  levels          one line of each log level");
  Serial.println("  burst [n]       n numbered lines as fast as possible (default 600)");
  Serial.println("  malformed       lines that must show as plain text, not data");
  Serial.println("  long            a 300-character line");
  Serial.println("  utf8            non-ASCII text");
  Serial.println("  partial         one line sent in three pieces");
  Serial.println("  blank           empty and whitespace-only lines");
  Serial.println("  led on|off      set the built-in LED");
}

void printStatus() {
  Serial.print("INFO:streaming=");
  Serial.print(streaming ? "on" : "off");
  Serial.print(" rate=");
  Serial.print(rateHz);
  Serial.print("Hz gap=");
  Serial.print(gapMode ? "on" : "off");
  Serial.print(" slow=");
  Serial.print(slowSensor ? "on" : "off");
  Serial.print(" led=");
  Serial.println(ledOn ? "on" : "off");
}

void setRate(long hz) {
  if (hz < 1 || hz > (long)MAX_RATE_HZ) {
    Serial.print("ERROR:rate must be 1-");
    Serial.println(MAX_RATE_HZ);
    return;
  }
  rateHz = hz;
  Serial.print("INFO:rate set to ");
  Serial.print(rateHz);
  Serial.println(" Hz");
}

void printLevels() {
  Serial.println("ERROR:this is an error");
  Serial.println("WARN:this is a warning");
  Serial.println("INFO:this is info");
  Serial.println("DEBUG:this is debug");
  Serial.println("this is a plain log line");
  Serial.println("error:lowercase is plain text, not an error");
}

// Exceeds Gremlin's 500-line buffer to check trimming and UI responsiveness.
void burst(long count) {
  if (count < 1 || count > (long)MAX_BURST_LINES) {
    Serial.print("ERROR:burst must be 1-");
    Serial.println(MAX_BURST_LINES);
    return;
  }
  Serial.print("INFO:burst of ");
  Serial.print(count);
  Serial.println(" lines");
  for (long i = 1; i <= count; i++) {
    Serial.print("burst line ");
    Serial.println(i);
  }
  Serial.println("INFO:burst done");
}

void printMalformed() {
  Serial.println(":25");
  Serial.println("temp:");
  Serial.println("1sensor:25");
  Serial.println("temp:25,bad");
  Serial.println("temp:hot");
  Serial.println("INFO:the 5 lines above should be plain text");
}

void printLongLine() {
  for (unsigned int i = 0; i < LONG_LINE_LENGTH; i++) {
    Serial.print((char)('a' + i % 26));
  }
  Serial.println();
}

// Gremlin must hold the partial line until the newline arrives.
void printPartialLine() {
  Serial.print("partial line: one, ");
  Serial.flush();
  delay(300);
  Serial.print("two, ");
  Serial.flush();
  delay(300);
  Serial.println("three");
}

void setLed(String arg) {
  arg.toLowerCase();
  if (arg == "on" || arg == "off") {
    ledOn = arg == "on";
    digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
    Serial.print("INFO:led ");
    Serial.println(arg);
  } else {
    Serial.println("ERROR:usage: led on|off");
  }
}
