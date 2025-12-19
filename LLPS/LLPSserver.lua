local LLP_MESSAGE_PREFIX = CONNsetPreffixSuffix(Configs["LLP Prefix"])
local LLP_MESSAGE_SUFFIX = CONNsetPreffixSuffix(Configs["LLP Suffix"])

local LLPconnections = {} -- Variable to hold connections and their respective buffers
local LLP_TIMEOUT = Configs["Timeout After"]

local TimerID = nil
local Acks = {} -- Variable to hold pending ACKS

local function LLPpurgeIdleConnections()
   if not Configs["Enable Connection Timeout"] then return end
   local now = os.time()
   for socket, connection in pairs(LLPconnections) do
      if now - connection.ts > LLP_TIMEOUT then
         LogDebug("Closing idle " .. socket .. "\n"
            .. "Socket has been idle for: " .. now - connection.ts .. " seconds")
         socket:close()
      end
   end
end

--[[
This function behaves similar to a moving frame. Essentially any buffer that is sent to this function to extract messages
will start with the beginning delimiter character of a message. If that's not the case then that means that the previous
message failed to parse correctly, wrong data was sent or duplicate delimiters and will cause the component to error out

For a visual example see below, assume "S" is beginning delimiter, "E" is ending delimiter(s) and "-" are just data chunks
Here's a frame with two messages:
S - - - - - - - E S - - - - - - - E
^ Cursor

Next message frame:
<1st Msg Pushed>  S - - - - - - - E
                  ^ Cursor
]]
local function LLPparse(Buffer, Data)
   local BufferString = table.concat(Buffer, "")
   local PrefixLen, SuffixLen = #LLP_MESSAGE_PREFIX, #LLP_MESSAGE_SUFFIX
   if (#BufferString > 0 and BufferString:find(LLP_MESSAGE_PREFIX, 1, true) ~= 1) then
      error("Unexpected data at start of buffer: " .. BufferString:sub(1, 50))
   end
   local Consumed = 0
   local Messages = {}
   local Cursor = 1
   while true do
      -- Find next prefix from the cursor position
      local PrefixLoc = BufferString:find(LLP_MESSAGE_PREFIX, Cursor, true)
      if not PrefixLoc then break end -- No message present exit without consuming
      local MessageStart = PrefixLoc + PrefixLen
      -- Find the suffix after the prefix
      local Success, SuffixLoc = pcall(string.find, Data, LLP_MESSAGE_SUFFIX, 1+Cursor, true)
      if Success and SuffixLoc then
         SuffixLoc = SuffixLoc + #BufferString - #Data
      else
         SuffixLoc = nil
      end
      if not SuffixLoc then break end -- Incomplete message exit without consuming
      Messages[#Messages + 1] = BufferString:sub(MessageStart, SuffixLoc - 1)
      -- Advance cursor to right after the suffix
      Cursor = SuffixLoc + SuffixLen
      Consumed = SuffixLoc + SuffixLen - 1
   end
   -- This is whatever is left after the ending delimiter of the HL7
   for i = 1, #Buffer do
      Buffer[i] = nil -- Can't do Buffer = {} because that rebinds the local variable Buffer
   end
   Buffer[1] = BufferString:sub(Consumed + 1)
   local EmptyFlag = false -- If there's no data left in the buffer, reset it
   if #Buffer[1] > 0 and Buffer[1]:sub(1, #LLP_MESSAGE_PREFIX) ~= LLP_MESSAGE_PREFIX then
      iguana.logError("Unexpected data in buffer after parsing " .. #Messages .. " messages clearing buffer")
      EmptyFlag = true
   end
   if #Buffer[1] == 0 then
      EmptyFlag = true
   end
   return Messages, EmptyFlag
end

-- Check if it's any known TLS version
local function LLPisTLShandshake(Data)
   if #Data < 3 then return false end
   local byte1, byte2, byte3 = Data:byte(1, 3)
   return byte1 == 0x16 and byte2 == 0x03 and (
      byte3 == 0x00 or  -- SSL 3.0 (rare)
      byte3 == 0x01 or  -- TLS 1.0
      byte3 == 0x02 or  -- TLS 1.1
      byte3 == 0x03 or  -- TLS 1.2
      byte3 == 0x04     -- TLS 1.3
   )
end

local function SendAcks()
   for Connection, Ack in pairs(Acks) do
      local DestinationSocket = Connection.socket
      if LLPconnections[DestinationSocket] then
         for i = 1, #Ack do
            iguana.logInfo("Sending ACK back to client")
            Connection.socket:send(LLP_MESSAGE_PREFIX..Ack[i]..LLP_MESSAGE_SUFFIX)
         end
      else
         iguana.logError("Cannot send acknowledgment for this message because the connection is closed."
            .. "\nThe message may or may not have been processed successfully, please check the logs.")
      end
   end
   Acks = {}
   TimerID = nil
end

local function LLPonData(Connection, Data)

   -- 1) append data to buffer
   if not Connection.buffer then
      if Data:sub(1, #LLP_MESSAGE_PREFIX) ~= LLP_MESSAGE_PREFIX then
         iguana.logError("Unexpected data at start of buffer of " .. Connection.socket .. " clearing buffer")
         if Configs["SSL certificate"] == "" and LLPisTLShandshake(Data) then
            iguana.logError("SSL is off but client is trying to initiate SSL handshake")
         end
         return
      end
      Connection.buffer = {Data}
   else
      table.insert(Connection.buffer, Data)
   end

   -- 2) Check if there's an ending delimiter in the last two packets received (or one if only one was received)
   -- and extract all LLP messages if so
   local CurrentPacket
   if #Connection.buffer > 1 then
      CurrentPacket = Connection.buffer[#Connection.buffer-1] .. Data
   else
      CurrentPacket = Data
   end

   local success, messages
   if CurrentPacket:find(LLP_MESSAGE_SUFFIX, 1, true) then
      success, messages, EmptyFlag = pcall(LLPparse, Connection.buffer, CurrentPacket)
      if EmptyFlag then Connection.buffer = nil end

      if not success then

         local ErrorMessage = "Error: " .. messages .. "\nClosing " .. Connection.socket
         -- If there's unexpected data, add a note about non-printable characters (invisible) like new line and vertical tab
         if ErrorMessage:find("Unexpected data at start of buffer") then
            ErrorMessage = ErrorMessage .. "\nCheck the escaped view for non-printable characters. Clearing buffer"
         end
         Connection.buffer = {""}
         iguana.logError(ErrorMessage)
         Connection.socket:close()
         return

      end

   end

   -- 3) Process messages in main and generate ACKs - store them in the Acks variable.
   if messages then
      LogDebug("Found " .. #messages .. " messages")
      for _,message in ipairs(messages) do
         LogDebug("Extracted message:\n" .. message)

         local ack = main(message)
         if not Acks[Connection] then
            Acks[Connection] = {}
            table.insert(Acks[Connection], ack)
         else
            table.insert(Acks[Connection], ack)
         end

         -- 4) If we find messages then schedule a task to send the ACKs as soon as possible.
         --[[
         We schedule a task rather than do it here to allow for the onClose function to
         take place since it is asynchronous and will also be "scheduled" so we need to get out of
         the onData function first
         ]]
         if not TimerID then
            TimerID = component.setTimer{delay=0, callback=SendAcks}
         end
      end
   end
end

local function onData(Socket, Data)
   -- Log partial data (first and last 50 chars) if greater than 100 characters
   if #Data > 100 then
      LogDebug("Received data on " .. Socket .. ":\n" .. Data:sub(1, 50) .. " ... " .. Data:sub(#Data-50, #Data))
   else
      LogDebug("Received data on " .. Socket .. ":\n" .. Data)
   end
   if #Data > 0 then
      LLPonData(LLPconnections[Socket], Data)
   end
   LLPconnections[Socket].ts = os.time()
   LLPpurgeIdleConnections()
end

local function onWrite(Socket)   -- optional callback function
   LogDebug(Socket .. " is ready to receive more data")
   LLPconnections[Socket].ts = os.time()
   LLPpurgeIdleConnections()
end

local function onClose(Socket, Data, Err)
   if #Data > 0 then
      iguana.logWarning(Socket .. " closed with non-empty buffer: " .. Data:sub(1, 1024))
   end
   if Err then
      local ErrorMessage = Socket .. " closed due to error: " .. Err
      if Err:match('wrong version number') then
         ErrorMessage = ErrorMessage .. "\nTry verifying the SSL settings on the sender and receiver"
      end
      iguana.logError(ErrorMessage)
   end
   LogDebug(Socket .. " closed")
   LLPconnections[Socket] = nil
   LLPpurgeIdleConnections()
end

-- Set the callback functions
local function onAccept(Socket, ClientIp)
   LogDebug("New " .. Socket)
   Socket:setOnDataReceived(onData)
   Socket:setOnSendComplete(onWrite)
   Socket:setOnSocketClosed(onClose)
   LLPconnections[Socket] = {socket = Socket, ip = ClientIp, ts = os.time() }
   LLPpurgeIdleConnections()
end

function LLPstart()
   local Config = {
      port = Configs.Port,
      ssl = {
         cert = Configs["SSL Certificate"],
         key = Configs["SSL Key"],
         verify_peer = Configs["Verify Peer"],
         ca_file = Configs["Certificate Authority File"]
      },
      onAccept=onAccept
   }
   LogDebug("Configurations the LLP listener is using: " .. json.serialize{data=Config})
   net.tcpAsync.listen(Config)
end