import serverloggers
import std/[asyncdispatch]


proc useRsyslog() {.async.} =
  let logger = newRsyslogLogger()
  await logger.open("AsyncRsysLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  await logger.close()


proc useFileLog() {.async.}=
  var logger = newFileLogger("test.log")
  await logger.open("AsyncFileLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  await logger.close()

proc useConsoleLog() {.async.}=
  var logger = newConsoleLogger(false)
  await logger.open("AsyncConsoleLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  await logger.close()


waitFor(useRsyslog())
waitFor(useFileLog())
waitFor(useConsoleLog())
