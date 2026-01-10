from logging import nil
import std/[nativesockets, strutils, uri, os, tables, times]
export logging.Level

const useAsync = defined(useAsync)
const useThreads = compileOption("threads") and not useAsync



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
    tags: Table[string, string]

  ServerLogger = ref object of logging.Logger
    formatter: LoggerFormatter
    tagger: LoggerTagger
    name: string
    when useThreads:
      threadId: int = -1
    processId: int = -1

  ConsoleLoggerImpl = ref object of RootObj
    useStderr: bool
    flushThreshold: logging.Level

  ConsoleLogger* = ref object of ServerLogger
    impl: ConsoleLoggerImpl

  RsysLoggerImpl = ref object of RootObj
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

  RsyslogLogger* = ref object of ServerLogger
    impl: RsysLoggerImpl

  RsyslogLevels = enum
    LOG_EMERG       #  system is unusable
    LOG_ALERT       #  action must be taken immediately
    LOG_CRIT        #  critical conditions
    LOG_ERR         #  error conditions
    LOG_WARNING     #  warning conditions
    LOG_NOTICE      #  normal but significant condition
    LOG_INFO        #  informational
    LOG_DEBUG       #  debug-level messages


when defined(macosx):
  const DEFAULT_URL = "unix:///var/run/syslog"
else:
  const DEFAULT_URL = "unix:///dev/log"

const DEFAULT_FORMAT = "%(asctime).%(msecs) %(process) %(levelname) %(filename):%(lineno)] %(name) %(tags) %(message)"
const YEAR_MONTH_DAY = "yyyy-MM-dd"
const HOUR_MINUTE_SECOND = "hh:mm:ss"
const DATE_FORMAT = YEAR_MONTH_DAY & " " & HOUR_MINUTE_SECOND
const DATE_FORMAT_LENGHT = DATE_FORMAT.len
const MSECS_LEN = 3


let convTable: array[logging.Level, RsyslogLevels] = [
  LOG_DEBUG, LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING, LOG_ERR, LOG_EMERG, LOG_DEBUG
]

let namesTable: array[logging.Level, char] = [
  'D', 'D', 'I', 'N', 'W', 'E', 'F', 'D'
]


proc len(self: LoggerTagger): int =
  result = 2 # {}
  var keys = 0
  for k,v in self.tags.pairs:
    result.inc(k.len+1) # incl :
    result.inc(v.len)
    keys.inc
  if keys > 1:
    result.inc(keys-1) # adding separating commas


proc clone(self: LoggerTagger): LoggerTagger =
  result.tags = self.tags


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
        i.inc
      else:
        self.fmt.add(fmt[i].uint8)
    i.inc


func numLen(n: int): int {.inline.} =
  if n > 999999:
    result = 7
  elif n > 99999:
    result = 6
  elif n > 9999:
    result = 5
  elif n > 999:
    result = 4
  elif n > 99:
    result = 3
  elif n > 9:
    result = 2
  else:
    result = 1


proc initLogger(self: ServerLogger, levelThreshold: logging.Level, fmtStr: string) =
  self.levelThreshold = levelThreshold
  self.formatter.prepareFormat(fmtStr)
  when useThreads:
    self.threadId = getThreadId()
  self.processId = getCurrentProcessId()


proc clone(src, dest: ServerLogger) =
  dest.levelThreshold = src.levelThreshold
  dest.formatter = src.formatter
  when useThreads:
    dest.threadId = src.threadId
  dest.processId = src.processId


proc buildMessage(self: ServerLogger, level: logging.Level, filename, lineno, message: openArray[char]): string =
  var strlen = 0
  for code in self.formatter.fmt:
    case code
    of LF_NAME.uint8:
      strlen.inc(self.name.len)
    of LF_LEVEL_NO.uint8:
      strlen.inc
    of LF_LEVEL_NAME.uint8:
      strlen.inc
    of LF_FILE_NAME.uint8:
      strlen.inc(filename.len)
    of LF_LINE_NO.uint8:
      strlen.inc(lineno.len)
    of LF_ASCTIME.uint8:
      strlen.inc(DATE_FORMAT_LENGHT)
    of LF_MSECS.uint8:
      strlen.inc(MSECS_LEN)
    of LF_THREAD_ID.uint8:
      when useThreads:
        if self.threadId >= 0:
          strlen.inc(self.threadId.numLen)
        else:
          # thread ID is -1
          strlen.inc(2)
    of LF_PROCESS_ID.uint8:
      if self.processId >= 0:
        strlen.inc(self.processId.numLen)
      else:
        # process ID is -1
        strlen.inc(2)
    of LF_TAGS.uint8:
      strlen.inc(self.tagger.len)
    of LF_MESSAGE.uint8:
      strlen.inc(message.len)
    else:
      strlen.inc
  result.setLen(strlen)
  var destUnchecked = cast[ptr UncheckedArray[char]](result[0].addr)
  var at = 0
  template add(ds: ptr UncheckedArray[char], c: char) =
    ds[at] = c
    at.inc
  template add(ds: ptr UncheckedArray[char], s: openArray[char]) =
    for c in s:
      ds.add(c)
  let ts = now()
  for code in self.formatter.fmt:
    case code
    of LF_NAME.uint8:
      for n in self.name:
        destUnchecked.add(n)
    of LF_LEVEL_NO.uint8:
      destUnchecked.add(('0'.uint8+level.uint8).char)
    of LF_LEVEL_NAME.uint8:
      destUnchecked.add(namesTable[level])
    of LF_FILE_NAME.uint8:
      for n in filename:
        destUnchecked.add(n)
    of LF_LINE_NO.uint8:
      destUnchecked.add(lineno)
    of LF_ASCTIME.uint8:
      destUnchecked.add(ts.format(DATE_FORMAT))
    of LF_MSECS.uint8:
      let ms = $convert(Nanoseconds, Milliseconds, ts.nanosecond)
      var msecs = MSECS_LEN
      if ms.len < MSECS_LEN:
        let leading0 = MSECS_LEN-ms.len
        for n in 0..<leading0:
          destUnchecked.add('0')
        msecs = ms.len
      for n in 0..<msecs:
        destUnchecked.add(ms[n])
    of LF_THREAD_ID.uint8:
      when useThreads:
        if self.threadId >= 0:
          destUnchecked.add($self.threadId)
        else:
          destUnchecked.add('-')
          destUnchecked.add('1')
    of LF_PROCESS_ID.uint8:
      if self.processId >= 0:
        destUnchecked.add($self.processId)
      else:
        destUnchecked.add('-')
        destUnchecked.add('1')
    of LF_TAGS.uint8:
      destUnchecked.add('{')
      if self.tagger.tags.len > 0:
        var notFirst = false
        for k,v in self.tagger.tags.pairs:
          if notFirst:
            destUnchecked.add(',')
          destUnchecked.add(k)
          destUnchecked.add(':')
          destUnchecked.add(v)
          notFirst = true
      destUnchecked.add('}')
    of LF_MESSAGE.uint8:
      destUnchecked.add(message)
    else:
      destUnchecked.add(code.char)


proc newConsoleLogger*(
  useStderr = false,
  flushThreshold = logging.lvlError,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
): ConsoleLogger =
  result.new
  result.impl.new
  result.impl.useStderr = useStderr
  result.impl.flushThreshold = flushThreshold
  result.initLogger(levelThreshold, fmtStr)


proc open*(self: ConsoleLogger) =
  if self notIn logging.getHandlers():
    logging.addHandler(self)


proc close*(self: ConsoleLogger) =
  logging.removeHandler(self)


proc clone*(self: ConsoleLogger): ConsoleLogger =
  result.new
  self.clone(result)
  result.impl = self.impl
  result.tagger = self.tagger.clone


method log*(logger: ConsoleLogger, level: logging.Level, args: varargs[string, `$`]) {.gcsafe.} =
  if level >= logger.levelThreshold:
    let msg = logger.buildMessage(level, args[0], args[1], args[2])
    try:
      var handle = stdout
      if logger.impl.useStderr:
        handle = stderr
      writeLine(handle, msg)
      if level >= logger.impl.flushThreshold: flushFile(handle)
    except IOError:
      discard


template encodePriority(facility: RsyslogFacilities, priority: RsyslogLevels): int = facility.int.shl(3) or priority.int


proc newRsyslogLogger*(
  url = DEFAULT_URL,
  facility: RsyslogFacilities = FAC_USER,
  useTcpSock = false,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
): RsyslogLogger =
  result.new
  result.initLogger(levelThreshold, fmtStr)
  result.impl.new
  result.impl.facility = facility
  result.impl.useTcpSock = useTcpSock
  result.impl.isConnected = false
  let parsed = url.parseUri()
  if parsed.scheme == "unix" or parsed.hostname == "" or parsed.port == "":
    result.impl.useUnixSock = true
    result.impl.host = parsed.path
  else:
    result.impl.host = parsed.hostname
    result.impl.port = parsed.port.parseBiggestInt().Port
  when useThreads:
    result.impl.sLock.initLock()


when useAsync:
  proc connectUnixSocket(self: RsyslogLogger) {.async.} =
    if not self.impl.isConnected:
      try:
        await self.impl.socket.connectUnix(self.impl.host)
        self.impl.isConnected = true
      except OSError:
        self.impl.socket.close()
        self.impl.isConnected = false
        raise

  proc connectNonUnix(self: RsyslogLogger) {.async.} =
    if not self.impl.isConnected:
      try:
        await self.impl.socket.connect(self.impl.host, self.impl.port)
        self.impl.isConnected = true
      except OSError:
        self.impl.socket.close()
        self.impl.isConnected = false
        raise

  proc open*(self: RsyslogLogger) {.async.} =
    if self.impl.useUnixSock:
      self.impl.socket = newAsyncSocket(AF_UNIX, (if self.impl.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE)
    elif self.impl.useTcpSock:
      self.impl.socket = newAsyncSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    else:
      self.impl.socket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
    if self.impl.useUnixSock:
      await self.connectUnixSocket()
    else:
      await self.connectNonUnix()
    if self notIn logging.getHandlers():
      logging.addHandler(self)

  proc close*(self: RsyslogLogger) {.async.} =
    if self.impl.isConnected:
      self.impl.socket.close()
      self.impl.isConnected = false
    logging.removeHandler(self)

  method log*(logger: RsyslogLogger, level: logging.Level, args: varargs[string, `$`]) =
    proc realsend(msg: string) {.async.} =
      if logger.impl.useUnixSock or logger.impl.useTcpSock:
        await logger.impl.socket.send(msg)
      else:
        await logger.impl.socket.sendTo(logger.impl.host, logger.impl.port, msg)
    if level >= logger.levelThreshold:
      let prio = encodePriority(logger.impl.facility, convTable[level])
      let msg = $prio & logger.buildMessage(level, args[0], args[1], args[2]) & "\x00"
      if not logger.impl.isConnected:
        if logger.impl.useUnixSock:
          waitFor logger.connectUnixSocket()
        else:
          waitFor logger.connectNonUnix()
      try:
        waitFor(msg.realsend)
      except IOError:
        discard
else:
  template whenNeedLock(l: Lock, body: untyped) =
    when useThreads:
      withLock(l):
        body
    else:
      body

  proc connectUnixSocket(self: RsyslogLogger) =
    try:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.connectUnix(self.impl.host)
      self.impl.isConnected = true
    except OSError:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
      raise

  proc connectNonUnix(self: RsyslogLogger) =
    try:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.connect(self.impl.host, self.impl.port)
      self.impl.isConnected = true
    except OSError:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
      raise

  proc open*(self: RsyslogLogger) =
    whenNeedLock(self.impl.sLock):
      if self.impl.useUnixSock:
        self.impl.socket = newSocket(AF_UNIX, (if self.impl.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE)
      elif self.impl.useTcpSock:
        self.impl.socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
      else:
        self.impl.socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
    if self.impl.useUnixSock:
      self.connectUnixSocket()
    else:
      self.connectNonUnix()
    if self notIn logging.getHandlers():
      logging.addHandler(self)

  proc close*(self: RsyslogLogger) =
    if self.impl.isConnected:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
    logging.removeHandler(self)

  method log*(logger: RsyslogLogger, level: logging.Level, args: varargs[string, `$`]) =
    if level >= logger.levelThreshold:
      let prio = encodePriority(logger.impl.facility, convTable[level])
      let msg = $prio & logger.buildMessage(level, args[0], args[1], args[2]) & "\x00"
      if not logger.impl.isConnected:
        if logger.impl.useUnixSock:
          logger.connectUnixSocket()
        else:
          logger.connectNonUnix()
      try:
        if logger.impl.useUnixSock or logger.impl.useTcpSock:
          whenNeedLock(logger.impl.sLock):
            logger.impl.socket.send(msg)
        else:
          whenNeedLock(logger.impl.sLock):
            logger.impl.socket.sendTo(logger.impl.host, logger.impl.port, msg)
      except IOError:
        discard


proc clone*(self: RsyslogLogger): RsyslogLogger =
  result.new
  self.clone(result)
  result.impl = self.impl
  result.tagger = self.tagger.clone

proc tag*(self: ServerLogger, key: string, value: SomeNumber | SomeFloat) =
  self.tagger.tags["\"" & key & "\""] = $value # json key is always a string


proc tag*(self: ServerLogger, key: string, value: string) =
  self.tagger.tags["\"" & key & "\""] = "\"" & value & "\"" # json key is always a string, string value is also a json string


template log*(lvl: logging.Level, message: string): untyped =
  const (fname, lnum, _) = instantiationInfo()
  logging.log(lvl, fname, lnum, message)
