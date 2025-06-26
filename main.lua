require "CARDupdate"
require "STAT.STATstatus"
require "VALID.VALIDsetEncoding"
require "VALID.VALIDerrorCheck"
require "CONN.CONNsetPrefixSuffix"
require "ACK.ACKcustomAck"
require "ACK.ACKfastAck"
require "LLPS.LLPSserver"

local Configs = component.fields()

-- The main function is called when a message is received by the server
-- An ACKnowledgement message must be returned when it exits
function main(Message)
   if (Message == "INIT") then
      if Configs.MessageEncoding == '' then
         VALIDsetEncoding()
      end
      VALIDerrorCheck()
      LLPstart()
      return
   end
   Message = iconv.convert(Message, Configs.MessageEncoding, 'UTF-8')
   local MessageId = queue.push{data=Message}
   local Ack
   if Configs.AckGeneration == 'Fast' then
      Ack = ACKfastAck(Message)
   else
      Ack = ACKcustomAck(Message)
   end
   iguana.logInfo("#ack Generated ACK\n"..Ack, MessageId)
   ui.setStatusMessage{data=CARDupdate("Data last received at", os.date("%Y/%m/%d %H:%M:%S"))}
   return Ack
end