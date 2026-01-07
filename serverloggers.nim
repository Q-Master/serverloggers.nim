from logging import nil
import std/[nativesockets, strutils, uri, os, tables]

const useThreads {.used.} = compileOption("threads")
const useAsync = defined(useAsync)


when useAsync:
  import std/[asyncdispatch, asyncnet]
else:
  import std/[net]
  when useThreads:
    import std/[locks]


type
  RsyslogFacilities* = enum
    FAC_KERN       #  kernel messages
    FAC_USER       #  random user-level messages
    FAC_MAIL       #  mail system
    FAC_DAEMON     #  system daemons
    FAC_AUTH       #  security/authorization messages
    FAC_SYSLOG     #  messages generated internally by syslogd
    FAC_LPR        #  line printer subsystem
    FAC_NEWS       #  network news subsystem
    FAC_UUCP       #  UUCP subsystem
    FAC_CRON       #  clock daemon
    FAC_AUTHPRIV   #  security/authorization messages (private)
    FAC_FTP        #  FTP daemon
    FAC_NTP        #  NTP subsystem
    FAC_SECURITY   #  Log audit
    FAC_CONSOLE    #  Log alert
    FAC_SOLCRON    #  Scheduling daemon (Solaris)
    #  other codes through 15 reserved for system use
    FAC_LOCAL0      #  reserved for local use
    FAC_LOCAL1      #  reserved for local use
    FAC_LOCAL2      #  reserved for local use
    FAC_LOCAL3      #  reserved for local use
    FAC_LOCAL4      #  reserved for local use
    FAC_LOCAL5      #  reserved for local use
    FAC_LOCAL6      #  reserved for local use


  LoggerFormatters {.size: sizeof(uint8), pure.} = enum
    LF_NAME         ## Name of the logger (logging channel)
    LF_LEVEL_NO     ## Numeric logging level for the message (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    LF_LEVEL_NAME   ## Text logging level for the message ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
    LF_FILE_NAME    ## Filename portion of pathname
    LF_LINE_NO      ## Source line number where the logging call was issued (if available)
    LF_ASCTIME      ## Textual time when the log record was created by default YYYY-mm-dd HH:MM:SS
    LF_MSECS        ## Millisecond portion of the creation time rounded to 3 leading digits
    LF_THREAD_ID    ## Thread ID (if available)
    LF_PROCESS_ID   ## Process ID (if available)
    LF_TAGS         ## Tags attached to the logger in simple JSON notation
    LF_MESSAGE      ## The message of a log record

  LoggerFormatter = object
    fmt: seq[uint8]

  LoggerTagger = object
    tags: seq[Table[string, string]]

  ServerLogger = ref object of logging.Logger
    formatter: LoggerFormatter
    tags: LoggerTagger
    name: string
    when useThreads:
      threadId: int = -1
    processId: int = -1


  ConsoleLogger* = ref object of ServerLogger

  RsyslogLogger* = ref object of ServerLogger
    when useAsync:
      socket: AsyncSocket
    else:
      when useThreads:
        sLock: Lock
        socket {.guard: sLock.}: Socket
      else:
        socket: Socket
    useUnixSock: bool
    useTcpSock: bool
    host: string
    port: Port
    facility: RsyslogFacilities
    isConnected: bool

  RsyslogLevels = enum
    LOG_EMERG       #  system is unusable
    LOG_ALERT       #  action must be taken immediately
    LOG_CRIT        #  critical conditions
    LOG_ERR         #  error conditions
    LOG_WARNING     #  warning conditions
    LOG_NOTICE      #  normal but significant condition
    LOG_INFO        #  informational
    LOG_DEBUG       #  debug-level messages


const DEFAULT_URL = "unix://localhost:514"


let convTable: array[logging.Level, RsyslogLevels] = [
  LOG_DEBUG, LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING, LOG_ERR, LOG_EMERG, LOG_DEBUG
]

let namesTable: array[logging.Level, char] = [
  'D', 'D', 'I', 'N', 'W', 'E', 'F', 'D'
]

template encodePriority(facility: RsyslogFacilities, priority: RsyslogLevels): int =
  return (facility.int << 3) | priority.int


proc prepareFormat(self: var LoggerFormatter, fmt: string) =
  self.fmt = @[]
  var token: bool = false
  var tokenStr: string
  var i = 0
  while i < fmt.len:
    if token:
      if fmt[i] in Letters:
        tokenStr.add(fmt[i])
      elif fmt[i] == ')':
        token = false
        case tokenStr.toLowerAscii
        of "name": self.fmt.add(LF_NAME.uint8)
        of "levelno": self.fmt.add(LF_LEVEL_NO.uint8)
        of "levelname": self.fmt.add(LF_LEVEL_NAME.uint8)
        of "filename": self.fmt.add(LF_FILE_NAME.uint8)
        of "lineno": self.fmt.add(LF_LINE_NO.uint8)
        of "asctime": self.fmt.add(LF_ASCTIME.uint8)
        of "msecs": self.fmt.add(LF_MSECS.uint8)
        of "thread": self.fmt.add(LF_THREAD_ID.uint8)
        of "process": self.fmt.add(LF_PROCESS_ID.uint8)
        of "tags": self.fmt.add(LF_TAGS.uint8)
        of "message": self.fmt.add(LF_MESSAGE.uint8)
      else:
        token = false
        self.fmt.add('%'.uint8)
        self.fmt.add('('.uint8)
        for td in tokenStr:
          self.fmt.add(td.uint8)
    else:
      if fmt[i] == '%' and i+1 < fmt.len and fmt[i+1] == '(':
        token = true
        tokenStr = ""
      else:
        self.fmt.add(fmt[i].uint8)

proc initLogger(self: ServerLogger, levelThreshold: logging.Level, fmtStr: string) =
  self.levelThreshold = levelThreshold
  self.formatter.prepareFormat(fmtStr)
  when useThreads:
    self.threadId = getThreadId()
  self.processId = getCurrentProcessId()



#[
    __DEFAULT_FMT = '%(asctime).%(msecs) %(process) %(levelname) %(filename):%(lineno)] %(name) %(tags) %(message)'
    __DEFAULT_DATE_FMT = '%Y-%m-%d %H:%M:%S'
]#

#[

import logging, strutils

var logger = newConsoleLogger(fmtStr = "[$time][$levelid]")
addHandler(logger)

template log*(lvl: Level, data: string): untyped =
  let pos {.compiletime.} = instantiationInfo()
  const
    addition =
      when defined(release):
        "[$1] " % [pos.filename]
      else:
        "[$1:$2] " % [pos.filename, $pos.line]
  logger.log(lvl, addition & data)

template log*(data: string): untyped = log(lvlInfo, data)

log("hi world")

]#



proc newConsoleLogger*(
  levelThreshold = logging.lvlDebug,
  fmtStr = logging.defaultFmtStr
): ConsoleLogger =
  result.new
  result.initLogger(levelThreshold, fmtStr)


proc open*(self: ConsoleLogger) =
  if self notIn logging.getHandlers():
    logging.addHandler(self)


proc close*(self: ConsoleLogger) =
  logging.removeHandler(self)


proc newRsyslogLogger*(
  url = DEFAULT_URL,
  facility: RsyslogFacilities = FAC_USER,
  useTcpSock = false,
  levelThreshold = logging.lvlDebug,
  fmtStr = logging.defaultFmtStr
): RsyslogLogger =
  result.new
  result.facility = facility
  result.useTcpSock = useTcpSock
  result.initLogger(levelThreshold, fmtStr)
  result.isConnected = false
  let parsed = url.parseUri()
  if parsed.scheme == "unix" or parsed.hostname == "" or parsed.port == "":
    result.useUnixSock = true
    result.host = if parsed.scheme == "unix": parsed.hostname else: parsed.path
  else:
    result.host = parsed.hostname
    result.port = parsed.port.parseBiggestInt().Port
  when useThreads:
    result.sLock.initLock()


when useAsync:
  proc connectUnixSocket(self: RsyslogLogger) {.async.} =
    if not self.isConnected:
      try:
        await self.socket.connectUnix(self.host)
        self.isConnected = true
      except OSError:
        self.socket.close()
        self.isConnected = false
        raise

  proc connectNonUnix(self: RsyslogLogger) {.async.} =
    if not self.isConnected:
      try:
        await self.socket.connect(self.host, self.port)
        self.isConnected = true
      except OSError:
        self.socket.close()
        self.isConnected = false
        raise

  proc open*(self: RsyslogLogger) {.async.} =
    if self.useUnixSock:
      self.socket = newAsyncSocket(AF_UNIX, (if self.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE, buffered=false)
    elif useTcpSock:
      self.socket = newAsyncSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    else:
      self.socket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
    if self.useUnixSock:
      await self.connectUnixSocket()
    else:
      self.connectNonUnix()
    if self notIn getHandlers():
      addHandler(self)

  proc close*(self: RsyslogLogger) {.async.} =
    if self.isConnected:
      await self.socket.close()
      self.isConnected = false
    removeHandler(self)
else:
  template whenNeedLock(l: Lock, body: untyped) =
    when useThreads:
      withLock(l):
        body
    else:
      body

  proc connectUnixSocket(self: RsyslogLogger) =
    try:
      whenNeedLock(self.sLock):
        self.socket.connectUnix(self.host)
      self.isConnected = true
    except OSError:
      whenNeedLock(self.sLock):
        self.socket.close()
      self.isConnected = false
      raise

  proc connectNonUnix(self: RsyslogLogger) =
    try:
      whenNeedLock(self.sLock):
        self.socket.connect(self.host, self.port)
      self.isConnected = true
    except OSError:
      whenNeedLock(self.sLock):
        self.socket.close()
      self.isConnected = false
      raise

  proc open*(self: RsyslogLogger) =
    whenNeedLock(self.sLock):
      if self.useUnixSock:
        self.socket = newSocket(AF_UNIX, (if self.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE, buffered=false)
      elif self.useTcpSock:
        self.socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
      else:
        self.socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
    if self.useTcpSock:
      self.connectUnixSocket()
    else:
      self.connectNonUnix()
    if self notIn logging.getHandlers():
      logging.addHandler(self)

  proc close*(self: RsyslogLogger) =
    if self.isConnected:
      whenNeedLock(self.sLock):
        self.socket.close()
      self.isConnected = false
    logging.removeHandler(self)

