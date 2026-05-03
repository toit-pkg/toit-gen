import toit-gen show *

main:
  // Create a new Toit library representing a file.
  lib := Library "generated/hello.toit"
  lib.imports.add
      Import ["core"] --show-all

  // Create the main function.
  main-fn := Function "main"
      --parameters=[]
      --return-type=null
  
  // Create the body sequence and the print call.
  seq := Sequence
  print-fn := Function "print" --parameters=[] --return-type=null
  print-fn.name = "print"
  seq.call (Ref print-fn) (Literal "Hello, World!")
  main-fn.body = seq
  
  lib.functions.add main-fn

  // Wrap it in a program.

  program := Program
  program.libraries.add lib

  // Print the generated file in-memory.
  result := program.gen --in-memory
  print result["generated/hello.toit"]
