package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

Field_Error :: union {
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

field_init :: proc(n: int) -> (field: Binary_Finite_Field, err: Field_Error) {
	switch n {
	case 1:
		field.divisor = 3
	case 2:
		field.divisor = 7
	case 3:
		field.divisor = 11
	case 4:
		field.divisor = 19
	case 5:
		field.divisor = 37
	case 6:
		field.divisor = 67
	case 7:
		field.divisor = 131
	case:
		return field, Value_Error{reason = "n must be in [1, 7)"}
	}
	field.n = n
	field.order = 1 << uint(n)

	return field, nil
}

field_validate :: proc(field: Binary_Finite_Field, a: int) -> int {
	assert(a >= 0 && a < field.order)
	return a
}

field_add :: proc(field: Binary_Finite_Field, a, b: int) -> int {
	return field_validate(field, a) ~ field_validate(field, b)
}

field_negate :: proc(field: Binary_Finite_Field, a: int) -> int {
	return field_validate(field, a)
}

field_subtract :: proc(field: Binary_Finite_Field, a, b: int) -> int {
	return field_add(field, a, field_negate(field, b))
}

field_multiply :: proc(field: Binary_Finite_Field, a, b: int) -> int {
	if field.n == 1 do return field_validate(field, field_validate(field, a) * field_validate(field, b))

	field_validate(field, a)
	result := 0
	field_validate(field, b)
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
	div_len: uint = len(fmt.sbprintf(&sb, "%b", field.divisor))
	for result >= field.order {
		strings.builder_reset(&sb)
		res_len: uint = len(fmt.sbprintf(&sb, "%b", result))
		shift = res_len - div_len
		result ~= field.divisor << shift
	}
	return field_validate(field, result)
}

field_invert :: proc(field: Binary_Finite_Field, a: int) -> (value: int, err: Field_Error) {
	if a == 0 do return a, No_Inverse{number = a}

	for b := 0; b < field.order; b += 1 {
		if field_multiply(field, a, b) == 1 do return b, nil
	}

	return a, No_Inverse{number = a}
}

field_divide :: proc(field: Binary_Finite_Field, a, b: int) -> (value: int, err: Field_Error) {
	field_validate(field, a)
	inverse := field_invert(field, b) or_return
	return field_multiply(field, a, inverse), nil
}

field_matrix4 :: proc(field: Binary_Finite_Field, a: int) -> (result: matrix[4, 4]int) {
	assert(field.n == 4)
	basis := 1
	for c := 0; c < field.n; c += 1 {
		p := field_multiply(field, a, basis)
		basis <<= 1
		for r := 0; r < field.n; r += 1 {
			result[r, c] = (p >> uint(r)) & 1
		}
	}
	return result
}

field_matrix3 :: proc(field: Binary_Finite_Field, a: int) -> (result: matrix[3, 3]int) {
	assert(field.n == 3)
	basis := 1
	for c := 0; c < field.n; c += 1 {
		p := field_multiply(field, a, basis)
		basis <<= 1
		for r := 0; r < field.n; r += 1 {
			result[r, c] = (p >> uint(r)) & 1
		}
	}
	return result
}

field_matrix2 :: proc(field: Binary_Finite_Field, a: int) -> (result: matrix[2, 2]int) {
	assert(field.n == 2)
	basis := 1
	for c := 0; c < field.n; c += 1 {
		p := field_multiply(field, a, basis)
		basis <<= 1
		for r := 0; r < field.n; r += 1 {
			result[r, c] = (p >> uint(r)) & 1
		}
	}
	return result
}

field_matrix_n :: proc($N: int, field: Binary_Finite_Field, a: int) -> (result: [N][N]int) {
	assert(field.n == N)
	basis := 1
	for c := 0; c < field.n; c += 1 {
		p := field_multiply(field, a, basis)
		basis <<= 1
		for r := 0; r < field.n; r += 1 {
			result[c][r] = (p >> uint(r)) & 1
		}
	}
	return result
}

field_matrix :: proc(field: Binary_Finite_Field, a: int) -> (result: [][]int) {
	field_validate(field, a)
	result = make([][]int, field.n)
	for r := 0; r < field.n; r += 1 {
		result[r] = make([]int, field.n)
	}
	basis := 1
	for c := 0; c < field.n; c += 1 {
		p := field_multiply(field, a, basis)
		basis <<= 1
		for r := 0; r < field.n; r += 1 {
			result[r][c] = (p >> uint(r)) & 1
		}
	}
	return result
}

field_matrix_deinit :: proc(m: [][]int) {
	for c in m {
		defer delete(c)
	}
	delete(m)
}

@(test)
test_field_matrix :: proc(t: ^testing.T) {
	fields: [dynamic]Binary_Finite_Field
	defer delete(fields)
	for i := 1; i <= 7; i += 1 {
		field, err := field_init(i)
		if err != nil {
			fmt.eprintf("cannot initialize binary finite field for %d: %v\n", i, err)
			return
		}
		append(&fields, field)
	}

	for i := 1; i <= 7; i += 1 {
		if i == 3 {
			mm := field_matrix3(fields[2], 6)
			ms := field_matrix_n(3, fields[2], 6)
			md := field_matrix(fields[2], 6)
			testing.expect(t, md[0][0] == 0)
			testing.expect(t, md[0][1] == 1)
			testing.expect(t, md[0][2] == 1)
			testing.expect(t, md[1][0] == 1)
			testing.expect(t, md[1][1] == 1)
			testing.expect(t, md[1][2] == 0)
			testing.expect(t, md[2][0] == 1)
			testing.expect(t, md[2][1] == 1)
			testing.expect(t, md[2][2] == 1)
			for r := 0; r < i; r += 1 {
				for c := 0; c < i; c += 1 {
					testing.expect(t, mm[r, c] == ms[c][r])
					testing.expect(t, mm[r, c] == md[r][c])
				}
			}
		}
		if i == 4 {
			mm := field_matrix4(fields[3], 4)
			ms := field_matrix_n(4, fields[3], 4)
			md := field_matrix(fields[3], 4)
			for r := 0; r < i; r += 1 {
				for c := 0; c < i; c += 1 {
					testing.expect(t, mm[r, c] == ms[c][r])
					testing.expect(t, mm[r, c] == md[r][c])
				}
			}
		}
		if i == 5 {
			ms := field_matrix_n(5, fields[i - 1], i)
			md := field_matrix(fields[i - 1], i)
			for r := 0; r < i; r += 1 {
				for c := 0; c < i; c += 1 {
					testing.expect(t, ms[c][r] == md[r][c])
				}
			}
		}
		// if i > 5 {
		// 	md := field_matrix(fields[i - 1], i)
		// 	// fmt.printf("matrix: %v\n", md)
		// }
	}

}

@(test)
test_field_add :: proc(t: ^testing.T) {
	fields: [dynamic]Binary_Finite_Field
	defer delete(fields)
	for i := 1; i <= 7; i += 1 {
		bff, err := field_init(i)
		if err != nil {
			fmt.eprintf("cannot initialize binary finite field for %d: %v\n", i, err)
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
			fmt.eprintf("cannot initialize binary finite field for %d: %v\n", i, err)
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
			fmt.eprintf("cannot initialize binary finite field for %d: %v\n", i, err)
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

