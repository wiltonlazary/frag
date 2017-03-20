import
  logging

when defined(android):
  {.emit: """
    #include <android/log.h>
  """.}
  proc native_log(level: string, a: cstring) =
      {.emit: """__android_log_write(ANDROID_LOG_INFO, level, `a`);""".}

  proc log*(a: varargs[string, `$`]) = native_log(LevelNames.DEBUG, a.join())
  proc logDebug*(a: varargs[string, `$`]) = native_log(LevelNames.DEBUG, a.join())
  proc logInfo*(a: varargs[string, `$`]) = native_log(LevelNames.INFO, a.join())
  proc logNotice*(a: varargs[string, `$`]) = native_log(LevelNames.NOTICE, a.join())
  proc logWarn*(a: varargs[string, `$`]) = native_log(LevelNames.WARN, a.join())
  proc logError*(a: varargs[string, `$`]) = native_log(LevelNames.ERROR, a.join())
  proc logFatal*(a: varargs[string, `$`]) = native_log(LevelNames.FATAL, a.join())

var consoleLogger : ConsoleLogger
var fileLogger : FileLogger

proc log*(args: varargs[string, `$`]) =
  logging.debug(args)

proc logDebug*(args: varargs[string, `$`]) =
  logging.debug(args)

proc logInfo*(args: varargs[string, `$`]) =
  logging.info(args)

proc logNotice*(args: varargs[string, `$`]) =
  logging.notice(args)

proc logWarn*(args: varargs[string, `$`]) =
  logging.warn(args)

proc logError*(args: varargs[string, `$`]) =
  logging.error(args)

proc logFatal*(args: varargs[string, `$`]) =
  logging.fatal(args)

proc init*(logFileName: string) =
  consoleLogger = newConsoleLogger()
  fileLogger = newFileLogger(logFileName)
  logging.addHandler(consoleLogger)
  logging.addHandler(fileLogger)
