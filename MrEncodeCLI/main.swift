//
//  main.swift
//  MrEncodeCLI
//
//  Canonical CLI entrypoint.
//  All CLI execution routes through EncodeRunner → EncodeEngine.
//

import Foundation


// Make logs appear immediately (especially when launched by scripts/droplets)
setbuf(stdout, nil)
setbuf(stderr, nil)

let code = EncodeRunner.run(arguments: CommandLine.arguments)
exit(Int32(code))
