#pragma once
#include <string.h>
using std::string;

#ifdef FMU_KINSOL
  #define DEFAULT_NLS "kinsol"
#else
  #define DEFAULT_NLS "newton"
#endif

#include <Core/SimulationSettings/IGlobalSettings.h>

class  FMUGlobalSettings : public IGlobalSettings
{

public:
    virtual  ~FMUGlobalSettings() {}
    ///< Start time of integration (default: 0.0)
    virtual double getStartTime() { return 0.0; }
    virtual void setStartTime(double) {}
    ///< End time of integraiton (default: 1.0)
    virtual double getEndTime() { return 1.0; }
    virtual void setEndTime(double) {}
    ///< Output step size (default: 20 ms)
    virtual double gethOutput() { return 20; }
    virtual void sethOutput(double) {}
    ///< Write out results ([false,true]; default: true)
    virtual bool getResultsOutput() { return false; }
    virtual void setResultsOutput(bool) {}
    virtual bool useEndlessSim() {return true; }
    virtual void useEndlessSim(bool) {}
    ///< Write out statistical simulation infos, e.g. number of steps (at the end of simulation); [false,true]; default: true)
    virtual bool getInfoOutput() { return false; }
    virtual void setInfoOutput(bool) {}
    virtual string    getOutputPath() { return "./"; }
    virtual LogSettings getLogSettings() {return LogSettings();}
    virtual void setLogSettings(LogSettings) {}
    virtual OutputPointType getOutputPointType() { return OPT_ALL; };
    virtual void setOutputPointType(OutputPointType) {};
    virtual void setOutputPath(string) {}
    virtual string    getSelectedSolver() { return "euler"; }
    virtual void setSelectedSolver(string) {}
    virtual string    getSelectedLinSolver() { return DEFAULT_NLS; }
    virtual void setSelectedLinSolver(string) {}
    virtual string    getSelectedNonLinSolver() { return DEFAULT_NLS; }
    virtual void setSelectedNonLinSolver(string) {}
    virtual void load(string xml_file) {};
    virtual void setResultsFileName(string) {}
    virtual string getResultsFileName() { return ""; }
    virtual void setRuntimeLibrarypath(string) {}
    virtual string getRuntimeLibrarypath() { return "";}
    virtual void setAlarmTime(unsigned int) {}
    virtual unsigned int getAlarmTime() {return 0;}
private:
};
