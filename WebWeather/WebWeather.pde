// Marko Grönroos 2011

#include <avr/pgmspace.h>
#include <DHT22.h>
#include <Wire.h>
#include <BMP085.h>
#include <LiquidCrystal.h>
#include <SPI.h>
#include <Ethernet.h>

// DHT22 for temperature and humidity
#define DHT22_PIN 7
DHT22 dht22(DHT22_PIN);

// BMP085 for air pressure
// Pins: 1=SDA, 2=SCL 3=XCLR 4=EQC 5=GND 6=VCC
BMP085 dps = BMP085();

// Ethernet and web server
// Uses pins 10-13 and 4
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192,168,1, 177 };
Server server(8042);

// LCD
// 1: GND
// 2: +5V
// 3: Contrast -> 10 kOhm potentiometer center pin
// 4: RS -> 9
// 5: RW -> GND
// 6: Enable -> 8
// 11: D4 -> 6
// 12: D5 -> 5
// 13: D6 -> 3
// 14: D7 -> 2

// initialize the library with the numbers of the interface pins
LiquidCrystal lcd(9, 8, 6, 5, 3, 2);

const char indexPageContent[] PROGMEM =
  "<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN'>\n"
  "<html>\n"
  "  <head>\n"
  "    <title>Arduino Weather Station</title>\n"
  "    <meta http-equiv='Content-Type' content='text/html; charset=utf-8'>"
  "    <script>\n"
  "function requestData()\n"
  "{ \n"
  "    var xhr;\n"
  "\n"
  "    // Try IE\n"
  "    try {  xhr = new ActiveXObject('Msxml2.XMLHTTP');   }\n"
  "    catch (e) \n"
  "    {\n"
  "        try {   xhr = new ActiveXObject('Microsoft.XMLHTTP');    }\n"
  "        catch (e2) \n"
  "        {\n"
  "          // Not IE, use standard API\n"
  "          try {  xhr = new XMLHttpRequest();     }\n"
  "          catch (e3) {  xhr = false;   }\n"
  "        }\n"
  "     }\n"
  "  \n"
  "    xhr.onreadystatechange  = function()\n"
  "    { \n"
  "         if(xhr.readyState  == 4)\n"
  "         {\n"
  "              if(xhr.status  == 200) {\n"
  "                  processResponse(xhr.responseText);\n"
  "              } else \n"
  "                 document.result.response.value='Error code ' + xhr.status;\n"
  "         }\n"
  "    }; \n"
  "\n"
  "   xhr.open('GET', '/data',  true); \n"
  "   xhr.send(null); \n"
  "} \n"
  "\n"
  "function processResponse(response)\n"
  "{\n"
  "    document.result.response.value='Received: '  + response; \n"
  "\n"
  "    fields = response.split(' ', 10);\n"
  "\n"
  "    document.result.temperature1.value = fields[1];\n"
  "    document.result.temperature2.value = fields[6];\n"
  "    document.result.humidity.value = fields[3];\n"
  "    document.result.pressure.value = fields[8];\n"
  "}\n"
  "\n"
  "var c=0;\n"
  "function timedCount()\n"
  "{\n"
  "    document.result.response.value='Requesting...'; \n"
  "    requestData();\n"
  "    t=setTimeout('timedCount()', 2000);\n"
  "}\n"
  "    </script>\n"
  "\n"
  "    <style>\n"
  "input.numeric-data {\n"
  "  width: 6em; text-align: right;\n"
  "  border: none;\n"
  "  font-size: 1em;\n"
  "}\n"
  "    </style>\n"
  "  </head>\n"
  "\n"
  "  <body>\n"
  "    <h1>Magi's Arduino Weather Station</h1>\n"
  "    <p>On-line sensor data from DHT22 temperature/humidity sensor and BMP085 temperature/pressure sensor. \n"
  "       The station sits on my desk indoors, so the temperature and humidity may be a bit off.</p> \n"
  "    <p>Served by a web server running in Arduino Uno with Ethernet Shield.</p>\n"
  "    <form name='result'>\n"
  "      <table>\n"
  "        <tdata>\n"
  "          <tr>\n"
  "            <td>Temperature</td>\n"
  "            <td><input type='text' name='temperature1' class='numeric-data'/>°C</td>\n"
  "            <td><input type='text' name='temperature2' class='numeric-data'/>°C</td>\n"
  "          </tr>\n"
  "          <tr>\n"
  "            <td>Humidity</td>\n"
  "            <td><input type='text' name='humidity' class='numeric-data'/> %</td>\n"
  "          </tr>\n"
  "          <tr>\n"
  "            <td>Pressure</td>\n"
  "            <td><input type='text' name='pressure' class='numeric-data'/> hPa</td>\n"
  "          </tr>\n"
  "        </tdata>\n"
  "      </table>\n"
  "\n"
  "      <input style='margin-top: 30px; width: 40em;' type='text' name='response' value='-'/>\n"
  "    </form>\n"
  "\n"
  "    <script>\n"
  "      document.result.response.value='Starting...'; \n"
  "      window.onload = timedCount();\n"
  "    </script>\n"
  "\n"
  "    <p>Ajax updates tested to work only with Firefox.</p>\n"
  "\n"
  "    <hr>\n"
  "    <address><a href='mailto:magi@iki.fi'>Marko Grönroos</a></address>\n"
  "  </body>\n"
  "</html>\n";

void setup(void)
{
  // start serial port
  Serial.begin(9600);
  Serial.println("DHT22 Test");

  lcd.begin(16, 2);
  lcd.clear();
  lcd.print("DHT22 + BMP085");
  lcd.setCursor(0,1);
  lcd.print("magi@iki.fi 2011");

  delay(2000);
  lcd.clear();
  lcd.print("IP Address:");
  lcd.setCursor(0,1);
  for (int i=0; i<4; i++) {
    if (i > 0)
      lcd.print(".");
    lcd.print(int(ip[i]));
  }

  // BMP085 pressure sensor
  dps.init();

  // Ethernet and web server
  Ethernet.begin(mac, ip);
  server.begin();
}

void printf1Dec(LiquidCrystal lcd, float value) {
  lcd.print(int(value));
  lcd.print(".");
  lcd.print(int((value-int(value))*10));
}

void displayDHT22() {
  Serial.print(dht22.getTemperatureC());
  Serial.print("C ");
  Serial.print(dht22.getHumidity());
  Serial.println("%");

  lcd.setCursor(0,0);
  printf1Dec(lcd, dht22.getTemperatureC());
  lcd.print("C ");

  lcd.print("Hm ");
  printf1Dec(lcd, dht22.getHumidity());
  lcd.print("%");
}

// Temperature and pressure data from BMP085
long tempr;
long pressure;
long alt;

void readPressure() {
  dps.getTemperature(&tempr);
  dps.getPressure(&pressure);
  dps.getAltitude(&alt);
}

void displayPressure() {
  dps.getTemperature(&tempr);
  dps.getPressure(&pressure);
  dps.getAltitude(&alt);

  lcd.setCursor(0,1);
  printf1Dec(lcd, tempr/10.0);
  lcd.print("C ");
  lcd.print(pressure/100.0);
  lcd.print("hPa");

  Serial.print(tempr/10.0);
  Serial.print("C ");
  Serial.print(pressure/100.0);
  Serial.print("hPa ");
}

void readAndDisplayDHT22() {
  DHT22_ERROR_t errorCode;

  Serial.print("Requesting data...");
  errorCode = dht22.readData();

  switch(errorCode) {
    case DHT_ERROR_NONE:
      Serial.print("Got Data ");
      displayDHT22();
      break;
    case DHT_ERROR_CHECKSUM:
      Serial.print("check sum error ");
      displayDHT22();
      break;
    case DHT_BUS_HUNG:
      Serial.println("BUS Hung ");
      break;
    case DHT_ERROR_NOT_PRESENT:
      Serial.println("Not Present ");
      break;
    case DHT_ERROR_ACK_TOO_LONG:
      Serial.println("ACK time out ");
      break;
    case DHT_ERROR_SYNC_TIMEOUT:
      Serial.println("Sync Timeout ");
      break;
    case DHT_ERROR_DATA_TIMEOUT:
      Serial.println("Data Timeout ");
      break;
    case DHT_ERROR_TOOQUICK:
      Serial.println("Polled to quick ");
      break;
  }
}

void handleRequest(Client& client) {
  client.print("DHT22 ");
  client.print(dht22.getTemperatureC());
  client.print(" C ");
  client.print(dht22.getHumidity());
  client.print(" %");
  client.print(" BMP085 ");
  client.print(tempr/10.0);
  client.print(" C ");
  client.print(pressure/100.0);
  client.println(" hPa");
}

#define BUFLEN 100
void indexPage(Client& client) {  
  Serial.print("Client status = ");
  Serial.println(int(client.status()));

  char buffer[BUFLEN+1];
  int pos = 0;
  do {
    strncpy_P(buffer, indexPageContent + pos, BUFLEN);
    buffer[BUFLEN] = '\x0';
    client.print(buffer);
    pos += BUFLEN;

    Serial.print("Sent ");
    Serial.println(strlen(buffer));
  } while (strlen(buffer) == BUFLEN);
}


#define URLBUFFERLEN 20

void webServerListen()
{
  // listen for incoming clients
  Client client = server.available();
  if (client) {
    // an http request ends with a blank line
    boolean currentLineIsBlank = true;
    int state = 0;
    char urlbuffer [URLBUFFERLEN];
    int  urlpos = 0;
    int page = 0;
    while (client.connected()) {
      if (client.available()) {
        char c = client.read();
        // if you've gotten to the end of the line (received a newline
        // character) and the line is blank, the http request has ended,
        // so you can send a reply
        if (c == '\n' && currentLineIsBlank) {
          // send a standard http response header
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();

          if (page == 2)
            handleRequest(client);
          else
            indexPage(client);

          // give the web browser time to receive the data
          delay(10);

          break;
        }
        if (c == '\n') {
          // you're starting a new line
          currentLineIsBlank = true;
        } 
        else if (c != '\r') {
          // you've gotten a character on the current line
          currentLineIsBlank = false;
          
          if (state == 0 && c == 'G')
            state = 1;
          else if (state == 1 && c == 'E')
            state = 2;
          else if (state == 2 && c == 'T')
            state = 3;
          else if (state == 3 && c == ' ')
            state = 4;
          else if (state == 4 && c != ' ' && urlpos < URLBUFFERLEN-1)
            urlbuffer[urlpos++] = c;
          else if (state == 4 && c == ' ' && urlpos < URLBUFFERLEN-1) {
            urlbuffer[urlpos] = '\x0';
            Serial.print("Got HTTP request: ");
            Serial.println(urlbuffer);
            if (strcmp(urlbuffer, "/data") == 0)
              page = 2;
            else if (strcmp(urlbuffer, "/") == 0)
              page = 1;
            state = 0;
            urlpos = 0;
          } else {
            state = 0;
            urlpos = 0;
          }
        }
      }
    }

    // give the web browser time to receive the data
    delay(1);

    // close the connection:
    client.stop();
  }
}

void loop(void)
{
  // Listen for clients for two seconds
  for (unsigned long lastSensorReadTime = millis(); millis()-lastSensorReadTime < 2000;) {
    webServerListen();
  }
  
  // Then read the sensors
  readPressure();
  displayPressure();
  readAndDisplayDHT22(); 
}

