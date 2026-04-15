import serverloggers

proc useConsoleLog() =
  var logger = newConsoleLogger()
  logger.open("ConsoleLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()

proc useRsysLog() =
  var logger = newRsyslogLogger()
  logger.open("SyncRsysLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()


useConsoleLog()
useRsysLog()
