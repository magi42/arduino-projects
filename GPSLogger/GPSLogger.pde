/**************************************************************
 * GPS Logger
 * Marko Grönroos 2011
 *
 * This implementation uses:
 * - HW Serial RX (pin 0) for reading from GPS
 * - HW Serial TX for debug output
 * - Soft Serial on pins 10,11 for logging
 **************************************************************/
#include <NewSoftSerial.h>
#include <TinyGPS.h>
#include <stdarg.h>
#include <avr/pgmspace.h>

/******************************************************************************
 * Definitions
 ******************************************************************************/

#define VERSION "0.1.0"

// #define DEBUGMODE 1

/* Logger module */
#define LOGGER_READY  '<'
#define LOGGER_PROMPT '>'

// How soon do we think we've lost fix (milliseconds)
#define AGE_LOST_FIX 5000

/******************************************************************************
 * Global objects
 ******************************************************************************/

// Use NSS for the OpenLog communications.
// RX must come from the TXO pin (3) from the OpenLog chip
// TX must go to the     RXI pin (2) in   the OpenLog chip
NewSoftSerial logger(10, 11); // RX,TX
const int loggerResetPin = 12;
boolean logging = false;

boolean havefix = false;

// Status pin
const int statusPin = 13;
boolean statusOn = false;
unsigned long statusTime = millis();

// Current output device
#ifdef DEBUGMODE
Print& out = Serial;
#else
Print& out = logger;
#endif

/* Formatted printing */
void sprintf(Print& out, char *fmt, ... ){
        char tmp[128]; // resulting string limited to 128 chars
        va_list args;
        va_start (args, fmt );
        vsnprintf(tmp, 128, fmt, args);
        va_end (args);
        out.print(tmp);
}

TinyGPS gps;

/******************************************************************************
 * Setup
 ******************************************************************************/
void setup() {
  pinMode(statusPin, OUTPUT);
  pinMode(loggerResetPin, OUTPUT);
  
  // We're using the hardware serial for both input
  // from the GPS with RX pin and debug output
  // with the TX pin.
  // GPS sends 57600 by default so have to use that
  Serial.begin(57600);
  
  // The OpenLog logger uses 9600 by default.
  logger.begin(9600);
  digitalWrite(loggerResetPin, LOW);
  delay(100);
  digitalWrite(loggerResetPin, HIGH);
  Serial.println("Waiting logger...");
  waitLoggerReady(logger, LOGGER_READY);
  Serial.println("Logger ready");

  digitalWrite(statusPin, statusOn? LOW:HIGH);
}

/******************************************************************************
 * Main loop
 ******************************************************************************/
void loop() {
  // Collect GPS data for 5 seconds
  bool newdata = false;
  unsigned long start = millis();
  while (millis() - start < 5000) {
    if (feedgps())
      newdata = true;

    // No GPX fix yet
    if ((!logging || !havefix) && millis() > statusTime+50) {
      digitalWrite(statusPin, (statusOn = !statusOn)? HIGH:LOW);
      statusTime = millis();
    }
  }

  if (newdata)
    gpsdump(gps, out);

  statusOn = !statusOn;
  digitalWrite(statusPin, statusOn? LOW:HIGH);
}

void printString(Print& out, const PROGMEM char* str) {
  while(true) {
    char c = pgm_read_byte_near(str++);
    if (!c)
      break;
    out.print(c);
  }
}

/******************************************************************************
 * Waits for the OpenLog device to be ready
 ******************************************************************************/
void waitLoggerReady(NewSoftSerial& logger, char expected) {
  statusTime = millis();
  while(1) {
    if(logger.available()) {
      char c = logger.read();
      Serial.print(c);
      if (c == expected)
        break;
    }

    if (millis() > statusTime+100) {
      digitalWrite(statusPin, (statusOn = !statusOn)? HIGH:LOW);
      statusTime = millis();
    }
    
    feedgps();
  }  

  digitalWrite(statusPin, (statusOn = false)? HIGH:LOW);
}

/******************************************************************************
 * Holds date and time
 ******************************************************************************/
class Date {
  public:
    int year;
    byte month, day, hour, minute, second, hundredths;
    
    Date() {
    }
    
    void print(Print& out) {
      sprintf(out, "%04d-%02d-%02dT%02d:%02d:%02d.%02dZ",
              year, int(month), int(day), int(hour), int(minute), int(second), int(hundredths));
    }
} date;

/******************************************************************************
 * Initializes the log
 *
 * - Creates a new file
 * - Builds GPX file header
 ******************************************************************************/

prog_char str_xmlheader[] PROGMEM =
    "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
    "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\"\n"
    "     creator=\"Magi's Logger\"\n"
    "     version=\"1.1\"\n"
    "     xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n"
    "     xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 "
    "http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
    "  <metadata>\n"
    "    <name>Magi's Arduino GPS Logger</name>\n"
    "    <author>\n"
    "        <name>Marko Grönroos</name>\n"
    "        <email>magi@iki.fi</email>\n"
    "        <link href=\"http://iki.fi/magi/\">\n"
    "          <text>Marko Grönroos Homepage</text>\n"
    "        </link>\n"
    "    </author>\n"
    "    <copyright>\n"
    "      <year>2011</year>\n"
    "    </copyright>\n"
    "    <link href=\"http://iki.fi/magi/\">\n"
    "      <text>Marko Grönroos Homepage</text>\n"
    "    </link>\n"
    "    <time>";

prog_char str_xmlheader_end[] PROGMEM =
    "</time>\n"
    "  </metadata>\n"
    "  <trk>\n"
    "    <src>Locosys LS20031</src>\n";

void initlog(Print& out) {
  printString(out, str_xmlheader);
  date.print(out);
  printString(out, str_xmlheader_end);
}

/******************************************************************************
 * Write GPS data to logger.
 *
 * Adapted from TinyGPS example.
 ******************************************************************************/
void gpsdump(TinyGPS &gps, Print& out) {
  long lat, lon;
  float flat, flon;
  unsigned long age, chars;

  gps.f_get_position(&flat, &flon, &age);
  gps.crack_datetime(&date.year, &date.month, &date.day, &date.hour, &date.minute, &date.second, &date.hundredths, &age);
  
  // If no fix yet
  if (age == TinyGPS::GPS_INVALID_AGE) {
    havefix = false;
    return;
  } else if (age > AGE_LOST_FIX) {
    if (havefix) {
      // Lost fix
      out.print("    </trkseg>\n");
      havefix = false;
    }
    return;
  } else if (!havefix) {
    // Gained fix
    havefix = true;

    if (!logging) {
      initlog(out);
      logging = true;
    }
    out.print("    <trkseg>\n");
  }
  feedgps(); // If we don't feed the gps during this long routine, we may drop characters and get checksum errors

  out.print("      <trkpt ");
  out.print("lat=\"");
  logFloat(flat, 5, out);
  out.print("\" lon=\"");
  logFloat(flon, 5, out);
  out.print("\">");
  feedgps();
  
  float alt = gps.f_altitude();
  out.print("<ele>");
  out.print(alt);
  out.print("</ele>");
  feedgps();

  // Date and time
  out.print("<date>");
  date.print(out);
  out.print("</date>");
  feedgps();

  out.print("<extensions>");
  float speed = gps.f_speed_kmph();
  out.print("<speed>");
  out.print(speed);
  out.print("</speed>");
  feedgps();

  float course = gps.f_course();
  out.print("<course>");
  out.print(course);
  out.print("</course>");
  feedgps();

  out.print("<fix-age>");
  out.print(age);
  out.print("</fix-age>");
  feedgps();

  out.print("</extensions></trkpt>\n");
  feedgps();
}

/******************************************************************************
 * Reads available GPS data.
 *
 * Copied from TinyGPS example.
 ******************************************************************************/
bool feedgps() {
  while (Serial.available()) {
    if (gps.encode(Serial.read()))
      return true;
  }
  return false;
}

/******************************************************************************
 * Logs a floating-point value with 5 decimal digits.
 *
 * Copied from TinyGPS example.
 ******************************************************************************/
void logFloat(double number, int digits, Print& out) {
  // Handle negative numbers
  if (number < 0.0) {
     out.print('-');
     number = -number;
  }

  // Round correctly so that print(1.999, 2) prints as "2.00"
  double rounding = 0.5;
  for (uint8_t i=0; i<digits; ++i)
    rounding /= 10.0;
  
  number += rounding;

  // Extract the integer part of the number and print it
  unsigned long int_part = (unsigned long)number;
  double remainder = number - (double)int_part;
  out.print(int_part);

  // Print the decimal point, but only if there are digits beyond
  if (digits > 0)
    out.print("."); 

  // Extract digits from the remainder one at a time
  while (digits-- > 0) {
    remainder *= 10.0;
    int toPrint = int(remainder);
    out.print(toPrint);
    remainder -= toPrint; 
  } 
}


