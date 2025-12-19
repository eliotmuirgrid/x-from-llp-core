require "STAT.STATstatus"

function CARDupdate(UpdateTitle,UpdateText)
   local R =''
   R = R .. STATrow(UpdateTitle, UpdateText)
   return R
end

function CARDwarning(Warning)
   local R =''
   R = R .. STATrow("Warning", Warning)
   return R
end