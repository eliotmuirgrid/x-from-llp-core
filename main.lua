-- From LLP Component - Version 1.1.1

Configs = component.fields() -- Load all configurations

require "CARDupdate"
require "STAT.STATstatus"
require "VALID.VALIDsetEncoding"
require "VALID.VALIDerrorCheck"
require "CONN.CONNsetPrefixSuffix"
require "ACK.ACKcustomAck"
require "ACK.ACKfastAck"
require "LLPS.LLPSserver"

-- The main function is called when a message is received by the server
-- An ACKnowledgement message must be returned when it exits
function main(Message)
   
   -- On start-up, set the encoding, perform error checking then start the listener
   if (Message == "INIT") then
      VALIDsetEncoding()
      VALIDerrorCheck()
      LLPstart()
      LogDebug("Listener started")
      return
   end
   
   -- 1) Convert the message to the specified encoding
   if component.live() then -- Safety check, otherwise translator will complain on "Use System Default" value
      Message = iconv.convert(Message, Configs["Message Encoding"], "UTF-8")
   end

   -- 2) Send the message downstream
   local MessageId = queue.push{data=Message}
   LogDebug("Message pushed downstream - generating ACK")
   
   -- 3) Generate Ack
   local Ack
   if Configs["Ack Generation"] == "Fast" then
      Ack = ACKfastAck(Message)
   else
      Ack = ACKcustomAck(Message)
   end
   
   iguana.logInfo("#ack Generated ACK\n"..Ack, MessageId)
   ui.setStatusMessage{data=CARDupdate("Data last received at", os.date("%Y/%m/%d %H:%M:%S"))}
   return Ack
end

-- Debug logs function
function LogDebug(Message)
   if Configs["Print Debug Logs"] then iguana.logDebug(Message) end
end