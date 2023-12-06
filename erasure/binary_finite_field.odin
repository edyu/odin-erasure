package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

BFF_Error :: union {
	Value_Error,
	No_Inverse,
}

Value_Error :: struct {
	reason: string,
}

No_Inverse :: struct {
	number: int,
}

Binary_Finite_Field :: struct {
	n:       int,
	order:   int,
	divisor: int,
}

field_init :: proc(n: int) -> (bff: Binary_Finite_Field, err: BFF_Error) {
	switch n {
	case 1:
		bff.divisor = 3
	case 2:
		bff.divisor = 7
	case 3:
		bff.divisor = 11
	case 4:
		bff.divisor = 19
	case 5:
		bff.divisor = 37
	case 6:
		bff.divisor = 67
	case 7:
		bff.divisor = 131
	case:
		return bff, Value_Error{reason = "n must be in [1, 7)"}
	}
	bff.n = n
	bff.order = 1 << uint(n)

	return bff, nil
}

field_validate :: proc(bff: Binary_Finite_Field, a: int) -> int {
	assert(a >= 0 && a < bff.order)
	return a
}

field_add :: proc(bff: Binary_Finite_Field, a, b: int) -> int {
	return field_validate(bff, a) ~ field_validate(bff, b)
}

field_negate :: proc(bff: Binary_Finite_Field, a: int) -> int {
	return field_validate(bff, a)
}

field_subtract :: proc(bff: Binary_Finite_Field, a, b: int) -> int {
	return field_add(bff, a, field_negate(bff, b))
}

field_multiply :: proc(bff: Binary_Finite_Field, a, b: int) -> int {
	if bff.n == 1 do return field_validate(bff, field_validate(bff, a) * field_validate(bff, b))

	field_validate(bff, a)
	result := 0
	field_validate(bff, b)
	sb: strings.Builder
	defer delete(sb.buf)
	bin_b := fmt.sbprintf(&sb, "%b", b)
	shift: uint = len(bin_b) - 1
	for d in bin_b {
		if d == '1' {
			result = result ~ (a << shift)
		}
		shift -= 1
	}
	strings.builder_reset(&sb)
	div_len: uint = len(fmt.sbprintf(&sb, "%b", bff.divisor))
	for result >= bff.order {
		strings.builder_reset(&sb)
		res_len: uint = len(fmt.sbprintf(&sb, "%b", result))
		shift = res_len - div_len
		result ~= bff.divisor << shift
	}
	return field_validate(bff, result)
}

field_invert :: proc(
	bff: Binary_Finite_Field,
	a: int,
) -> (
	value: int,
	err: BFF_Error,
) {
	if a == 0 do return a, No_Inverse{number = a}

	for b := 0; b < bff.order; b += 1 {
		if field_multiply(bff, a, b) == 1 do return b, nil
	}

	return a, No_Inverse{number = a}
}

field_divide :: proc(
	bff: Binary_Finite_Field,
	a, b: int,
) -> (
	value: int,
	err: BFF_Error,
) {
	field_validate(bff, a)
	inverse := field_invert(bff, b) or_return
	return field_multiply(bff, a, inverse), nil
}

@(test)
test_field_add :: proc(t: ^testing.T) {
	fields: [dynamic]Binary_Finite_Field
	defer delete(fields)
	for i := 1; i <= 7; i += 1 {
		bff, err := field_init(i)
		if err != nil {
			fmt.eprintf(
				"cannot initialize binary finite field for %d: %v\n",
				i,
				err,
			)
			return
		}
		append(&fields, bff)
	}

	for f in fields {
		negatives: map[int]int
		for a := 0; a < f.order; a += 1 {
			for b := 0; b < f.order; b += 1 {
				result := field_add(f, a, b)
				testing.expect(t, result >= 0 && result < f.order)
				testing.expect(t, result == field_add(f, b, a))
				if result == 0 {
					negatives[a] = b
					negatives[b] = a
				}
			}
		}
		testing.expect(t, f.order == len(negatives))
	}
}

@(test)
test_field_multiply :: proc(t: ^testing.T) {
	fields: [dynamic]Binary_Finite_Field
	defer delete(fields)
	for i := 1; i <= 7; i += 1 {
		bff, err := field_init(i)
		if err != nil {
			fmt.eprintf(
				"cannot initialize binary finite field for %d: %v\n",
				i,
				err,
			)
			return
		}
		append(&fields, bff)
	}

	for f in fields {
		reciprocals: map[int]int
		for a := 0; a < f.order; a += 1 {
			for b := 0; b < f.order; b += 1 {
				result := field_multiply(f, a, b)
				testing.expect(t, result >= 0 && result < f.order)
				testing.expect(t, result == field_multiply(f, b, a))
				if result == 0 {
					testing.expect(t, a == 0 || b == 0)
				}
				if result == 1 {
					testing.expect(t, !(a == 0 || b == 0))
					reciprocals[a] = b
					reciprocals[b] = a
				}
			}
		}
		testing.expect(t, f.order - 1 == len(reciprocals))
	}
}

@(test)
test_field_divide :: proc(t: ^testing.T) {
	fields: [dynamic]Binary_Finite_Field
	defer delete(fields)
	for i := 1; i <= 7; i += 1 {
		bff, err := field_init(i)
		if err != nil {
			fmt.eprintf(
				"cannot initialize binary finite field for %d: %v\n",
				i,
				err,
			)
			return
		}
		append(&fields, bff)
	}

	for f in fields {
		for a := 0; a < f.order; a += 1 {
			for b := 1; b < f.order; b += 1 {
				result, err := field_divide(f, a, b)
				if err != nil {
					fmt.eprintf("cannot field_divide %d by %d: %v\n", a, b, err)
					return
				}
				testing.expect(t, result >= 0 && result < f.order)
				if a == b {
					testing.expect(t, result == 1)
				} else {
					testing.expect(t, result != 1)
				}
			}
		}
	}
}
