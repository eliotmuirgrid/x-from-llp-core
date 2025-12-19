function VALIDsetEncoding()
   if Configs["Message Encoding"] == "Use System Default" then
      Configs["Message Encoding"] = os.posix() and 'ISO-8859-1' or 'Windows-1252'
   else
      Configs["Message Encoding"] = Configs["Message Encoding"]:match("%((.-)%)")
   end
   LogDebug(json.serialize{data=Configs}) -- Print the configurations
end