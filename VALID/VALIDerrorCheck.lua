-- Error checking to perform on component configurations

local function ValidHexFormat(input)
   -- Pattern to match a single \xNN sequence
   local pattern = "\\x[%dA-Fa-f][%dA-Fa-f]"
   -- Continuously match \xNN sequences until the end of the string
   local remaining = input
   while #remaining > 0 do
      local matched = string.match(remaining, "^" .. pattern)
      if not matched then
         return false -- If a sequence doesn't match, the input is invalid
      end
      -- Remove the matched sequence from the start of the string
      remaining = string.sub(remaining, #matched + 1)
   end
   return true
end

function VALIDerrorCheck()
   -- Remove white sapce from Prefix/suffix
   component.setField{key="LLP Prefix",value=Configs["LLP Prefix"]:gsub('%s','')}
   component.setField{key="LLP Suffix",value=Configs["LLP Suffix"]:gsub('%s','')}
   local Separator = os.posix() and [[/]] or [[\]]
   local SslValid = false

   -- Check port
   if Configs.Port <= 0 or Configs.Port == "" then
      error('Port field is empty or has invalid value.')
   end
   
   -- Check format of prefix and suffix
   if not (ValidHexFormat(Configs["LLP Prefix"]) and ValidHexFormat(Configs["LLP Suffix"])) then
      error('LLP Prefix/suffix is invalid.\nInput must begin with \\x and hex values must be between 0-9 and A-F.\nExample: \\x0B')
   end
   
   -- Check certificate and key files  
   if not (Configs["SSL Certificate"] == '') or not (Configs["SSL Key"] == '') then
      if (Configs["SSL Certificate"] == '') or (Configs["SSL Key"] == '') then error('Both SSL Certificate and SSL Key must be specified to use SSL.')
      elseif not (os.fs.access(Configs["SSL Certificate"])) then
         error('Unable to access SSL Certificate file:\n'..Configs["SSL Certificate"])      
      elseif not (os.fs.access(Configs["SSL Key"])) then
         error('Unable to access SSL Key file:\n'..Configs["SSL Key"])
      else
         SslValid = true
      end
   end
   
   -- Check verify peer
   if SslValid and Configs["Verify Peer"] then
      if (Configs["Certificate Authority File"] == '') then error('Certificate Authority File must be specified to use Verify Peer.')
      elseif not (os.fs.access(Configs["Certificate Authority File"])) then
         error('Unable to access Certificate Authority file:\n'..Configs["Certificate Authority File"])
      end
   elseif Configs["Verify Peer"] then error('SSL must be enabled to use Verify Peer') end
   
end