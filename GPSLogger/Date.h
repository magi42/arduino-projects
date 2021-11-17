
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
   
};
