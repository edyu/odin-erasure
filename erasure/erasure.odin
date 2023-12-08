package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Erasure_Error :: union {
	Field_Error,
	Unable_To_Read_File,
	Argument_Parse_Error,
	mem.Allocator_Error,
}

Argument_Parse_Error :: union {
	Missing_Argument,
	Wrong_Argument,
	Illegal_Argument,
}

Missing_Argument :: struct {
	field: string,
}

Wrong_Argument :: struct {
	field: string,
}

Illegal_Argument :: struct {
	reason: string,
}

Unable_To_Read_File :: struct {
	filename: string,
	error:    os.Errno,
}

Sub_Command :: union {
	Encode,
	Decode,
}

Encode :: struct {}

Decode :: struct {}

Command :: struct {
	sub:  Sub_Command,
	N:    int,
	K:    int,
	w:    int,
	file: string,
	code: string,
}

/*
    Usage: erasure [command] [options]
    
    Commands:
    
      encode              encode data
      decode              decode data
    
    General Options:
      -N | --num-code     code chunks in a block # default: 5
      -K | --num-data     data chunks in a block # default: 3
      -w | --word-size    bytes in a word in a chunks (1|2|4|8) # default: 8
    
      --file              name of data file: input for encoding and output for decoding
      --code              prefix of code files: output for encoding and input for decoding
*/
main :: proc() {
	context.logger = log.create_console_logger()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	usage :: `Usage: erasure [command] [options]
    
	    Commands:
    
	      encode              encode data
	      decode              decode data
    
	    General Options:
	      -N | --num-code     code chunks in a block # default: 5
	      -K | --num-data     data chunks in a block # default: 3
	      -w | --word-size    bytes in a word in a chunks (1|2|4|8) # default: 8

	      --file              name of data file: input for encoding and output for decoding
	      --code              prefix of code files: output for encoding and input for decoding
	`

	arguments := os.args[1:]
	fmt.println("args =", arguments)

	if len(arguments) < 5 {
		fmt.println(usage)
		os.exit(1)
	}

	command, cli_error := parse_arguments(arguments)

	if cli_error != nil {
		fmt.eprintln("Failed to parse arguments:", cli_error)
		os.exit(1)
	}

	switch c in command.sub {
	case Encode:
		do_encode(command)
	case Decode:
		do_decode(command)
	case:
		fmt.println(usage)
		os.exit(1)
	}

	// error := process_file(filename)
	// if error != nil {
	// fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
	// os.exit(1)
	// }
}

parse_int_argument :: proc(arg: string) -> (value: int, error: Argument_Parse_Error) {
	v := strconv.atoi(arg)
	if v > 0 do return v, nil
	return 0, Wrong_Argument{field = arg}
}

parse_arguments :: proc(arguments: []string) -> (command: Command, error: Argument_Parse_Error) {
	command.N = 5
	command.K = 3
	command.w = 8

	switch arguments[0] {
	case "encode":
		command.sub = Encode{}
	case "decode":
		command.sub = Decode{}
	case:
		return command, Wrong_Argument{field = arguments[0]}
	}

	args := arguments[1:]

	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-N", "--num-code":
			i += 1
			if i < len(args) {
				command.N = parse_int_argument(args[i]) or_return
			} else {
				return command, Missing_Argument{field = "num-code"}
			}
		case "-K", "--num-data":
			i += 1
			if i < len(args) {
				command.K = parse_int_argument(args[i]) or_return
			} else {
				return command, Missing_Argument{field = "num-data"}
			}
		case "-w", "--word-size":
			i += 1
			if i < len(args) {
				w := parse_int_argument(args[i]) or_return
				allowed: bit_set[1 ..= 8] = {1, 2, 4, 8}
				if w in allowed {
					command.w = w
				} else {
					return command, Wrong_Argument{field = args[i]}
				}
			} else {
				return command, Missing_Argument{field = "word-size"}
			}
		case "--file":
			i += 1
			if i < len(args) {
				command.file = args[i]
			} else {
				return command, Missing_Argument{field = "file"}
			}
		case "--code":
			i += 1
			if i < len(args) {
				command.code = args[i]
			} else {
				return command, Missing_Argument{field = "code"}
			}
		case:
			return command, Illegal_Argument{reason = args[i]}
		}
	}

	if command.N < command.K {
		return command, Illegal_Argument{reason = "1 <= K <= N"}
	}

	if command.file == "" {
		return command, Missing_Argument{field = "file"}
	}
	if command.code == "" {
		return command, Missing_Argument{field = "code"}
	}

	return command, nil
}

do_encode :: proc(c: Command) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("input=%s, shard=%s\n", c.file, c.code)
}

do_decode :: proc(c: Command) {
	fmt.printf("N=%d, K=%d, w=%d\n", c.N, c.K, c.w)
	fmt.printf("output=%s, shard=%s\n", c.file, c.code)
}

process_file :: proc(filename: string) -> Erasure_Error {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)

	return nil
}

