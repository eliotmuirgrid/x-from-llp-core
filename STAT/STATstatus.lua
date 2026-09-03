function STATrow(Label, Value)
   return [[<div class='CUSTrow'> 
<div class='CUSTlabel'>]]..Label..[[:</div>
<div class='CUSTvalue'>]]..Value..[[</div>
</div>   
]]
end

function STATerrorBlock(Error)
   return [[<div class='CUSTrow'>
   <div class='CUSTlabel'>Error:</div>
   <div class='CUSTerror CUSTvalue'>]]
        ..filter.html.enc(Error)..[[</div>
  </div>   
]]
end