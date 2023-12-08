package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:testing"

Finite_Field_Matrix :: struct {
	field:    Binary_Finite_Field,
	num_rows: int,
	num_cols: int,
	elements: [][]int,
}

matrix_init_cauchy :: proc(num_rows, num_cols: int, field: Binary_Finite_Field,
) -> (m: Finite_Field_Matrix, err: Field_Error,
) {
	m = matrix_init(num_rows, num_cols, field)
	matrix_set_cauchy(m) or_return
	return m, nil
}
	
matrix_init :: proc(
	num_rows, num_cols: int,
	field: Binary_Finite_Field,
) -> (m: Finite_Field_Matrix,
) {
	m.field = field
	m.num_rows = num_rows
	m.num_cols = num_cols
	m.elements = make([][]int, num_cols)
	for c := 0; c < num_cols; c += 1 {
		m.elements[c] = make([]int, num_rows)
	}
	return m
}

matrix_deinit :: proc(m: Finite_Field_Matrix) {
	for c := 0; c < m.num_cols; c += 1 {
		delete(m.elements[c])
	}
	delete(m.elements)
}

matrix_num_rows :: proc(m: Finite_Field_Matrix) -> int {
	return len(m.elements[0])
}

matrix_num_cols :: proc(m: Finite_Field_Matrix) -> int {
	return len(m.elements)
}

matrix_get :: proc(m: Finite_Field_Matrix, r, c: int) -> int {
	return m.elements[c][r]
}

matrix_set :: proc(m: Finite_Field_Matrix, r, c: int, v: int) {
	m.elements[c][r] = v
}

matrix_display :: proc(m: Finite_Field_Matrix) {
	fmt.print("matrix[")
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			fmt.print(matrix_get(m, r, c))
			if c < m.num_cols - 1 {
				fmt.print(", ")
			} else if r < m.num_rows - 1 {
				fmt.print("; ")
			}
		}
	}
	fmt.println("]")
}

matrix_set_cauchy :: proc(m: Finite_Field_Matrix) -> Field_Error {
	assert(m.field.order >= m.num_rows + m.num_cols)
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			matrix_set(
				m,
				r,
				c,
				field_invert(m.field, field_subtract(m.field, r + m.num_cols, c)) or_return,
			)
		}
	}
	return nil
}

matrix_submatrix :: proc(
	m: Finite_Field_Matrix,
	excluded_num_rows: []int,
	excluded_num_cols: []int,
) -> (
	sub: Finite_Field_Matrix,
) {
	sub_num_rows := m.num_rows - len(excluded_num_rows)
	sub_num_cols := m.num_cols - len(excluded_num_cols)
	sub = matrix_init(sub_num_rows, sub_num_cols, m.field)
	i := 0
	for r := 0; r < m.num_rows; r += 1 {
		if slice.contains(excluded_num_rows, r) do continue
		j := 0
		for c := 0; c < m.num_cols; c += 1 {
			if slice.contains(excluded_num_cols, c) do continue
			matrix_set(sub, i, j, matrix_get(m, r, c))
			j += 1
		}
		i += 1
	}
	return sub
}

matrix_determinant :: proc(m: Finite_Field_Matrix) -> (det: int) {
	assert(m.num_rows == m.num_cols)

	switch m.num_rows {
	case 1:
		return matrix_get(m, 0, 0)
	case:
		for c := 0; c < m.num_cols; c += 1 {
			sub := matrix_submatrix(m, {0}, {c})
			defer matrix_deinit(sub)
			sub_det := matrix_determinant(sub)
			x := field_multiply(m.field, matrix_get(m, 0, c), sub_det)

			if c % 2 == 1 {
				x = field_negate(m.field, x)
			}
			det = field_add(m.field, det, x)
		}
		return det
	}
}

matrix_cofactors :: proc(
	m: Finite_Field_Matrix,
) -> (
	cof: Finite_Field_Matrix,
) {
	assert(m.num_rows == m.num_cols)

	cof = matrix_init(m.num_rows, m.num_cols, m.field)
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			sub := matrix_submatrix(m, {r}, {c})
			defer matrix_deinit(sub)
			sub_det := matrix_determinant(sub)
			if (r + c) % 2 != 1 {
				matrix_set(cof, r, c, sub_det)
			} else {
				matrix_set(cof, r, c, field_negate(m.field, sub_det))
			}
		}
	}
	return cof
}

matrix_transpose :: proc(m: Finite_Field_Matrix) -> (x: Finite_Field_Matrix) {
	assert(m.num_rows == m.num_cols)

	x = matrix_init(m.num_rows, m.num_cols, m.field)
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			matrix_set(x, r, c, matrix_get(m, c, r))
		}
	}

	return x
}

matrix_scale :: proc(
	m: Finite_Field_Matrix,
	factor: int,
) -> (
	x: Finite_Field_Matrix,
) {
	assert(m.num_rows == m.num_cols)

	x = matrix_init(m.num_rows, m.num_cols, m.field)
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			matrix_set(x, r, c, field_multiply(m.field, matrix_get(m, r, c), factor))
		}
	}

	return x
}

matrix_invert :: proc(m: Finite_Field_Matrix) -> (x: Finite_Field_Matrix, err: Field_Error) {
	cof := matrix_cofactors(m)
	defer matrix_deinit(cof)
	txp := matrix_transpose(cof)
	defer matrix_deinit(txp)
	det := matrix_determinant(m)
	return matrix_scale(txp, field_invert(m.field, det) or_return), nil
}

matrix_multiply :: proc(
	a: Finite_Field_Matrix,
	b: Finite_Field_Matrix,
) -> (
	m: Finite_Field_Matrix,
) {
	assert(a.num_cols == b.num_cols)

	m = matrix_init(a.num_rows, b.num_cols, a.field)
	for r := 0; r < a.num_rows; r += 1 {
		for c := 0; c < b.num_cols; c += 1 {
			for i := 0; i < a.num_cols; i += 1 {
				x := matrix_get(m, r, c)
				y := matrix_get(a, r, i)
				z := matrix_get(b, i, c)
				matrix_set(m, r, c, field_add(a.field, x, field_multiply(a.field, y, z)))
			}
		}
	}

	return m
}

matrix_binary_rep :: proc(m: Finite_Field_Matrix) -> (x: Finite_Field_Matrix, err: Field_Error) {
	field := field_init(1) or_return
	x = matrix_init(m.num_rows * m.field.n, m.num_cols * m.field.n, field)
	for r := 0; r < m.num_rows; r += 1 {
		for c := 0; c < m.num_cols; c += 1 {
			a := matrix_get(m, r, c)
			mat_a := field_matrix(m.field, a)
			defer for i := 0; i < m.field.n; i += 1 do delete(mat_a[i])
			defer delete(mat_a)
			for i := 0; i < m.field.n; i += 1 {
				for j := 0; j < m.field.n; j += 1 {
					matrix_set(
						x,
						r * m.field.n + i,
						c * m.field.n + j,
						field_validate(m.field, mat_a[j][i]),
					)
				}
			}
		}
	}
	return x, nil
}

@(test)
test_matrix_display :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	m := matrix_init(4, 5, field)
	defer matrix_deinit(m)
	v := 1
	for i := 0; i < m.num_rows; i += 1 {
		for j := 0; j < m.num_cols; j += 1 {
			matrix_set(m, i, j, v)
			v += 1
		}
	}
	matrix_display(m)
}

@(test)
test_matrix_set_cauchy :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	m, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 2, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 3, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 1) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 3, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 3, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 0) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 4, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 1) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 4, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 2) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 4, 2)),
	)
}

@(test)
test_matrix_submatrix :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	i, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(i)

	m := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_cofactors :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	i, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(i)

	s := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(s)

	m := matrix_cofactors(s)
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_inverse :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	i, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(i)

	s := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(s)

	m, _ := matrix_invert(s)
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_determinant :: proc(t: ^testing.T) {
	a, _ := field_init(2)
	m, _ := matrix_init_cauchy(2, 2, a)
	defer matrix_deinit(m)
	det: int
	det = matrix_determinant(m)
	testing.expect(t, det == 1, fmt.tprintf("expected det: %v, got %v", 5, det))
	b, _ := field_init(3)
	m2, _ := matrix_init_cauchy(3, 3, b)
	defer matrix_deinit(m2)
	det = matrix_determinant(m2)
	testing.expect(t, det == 7, fmt.tprintf("expected det: %v, got %v", 7, det))
	c, _ := field_init(4)
	m3, _ := matrix_init_cauchy(4, 4, c)
	defer matrix_deinit(m3)
	det = matrix_determinant(m3)
	testing.expect(t, det == 7, fmt.tprintf("expected det: %v, got %v", 7, det))
}

@(test)
test_matrix_invertible_submatrices :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	m, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(m)

	num_num_rows_to_exclude := m.num_rows - m.num_cols
	for excluded_num_rows in choose({0, 1, 2, 3, 4}, num_num_rows_to_exclude) {
		fmt.printf("excluding %v...\n", excluded_num_rows)
		submatrix := matrix_submatrix(m, excluded_num_rows[:], {})
		defer matrix_deinit(submatrix)
		testing.expect(t, m.num_cols == submatrix.num_cols)
		inverse, _ := matrix_invert(submatrix)
		defer matrix_deinit(inverse)
		product1 := matrix_multiply(inverse, submatrix)
		defer matrix_deinit(product1)
		product2 := matrix_multiply(submatrix, inverse)
		defer matrix_deinit(product2)
		for r in 0 ..< product1.num_rows {
			for c in 0 ..< product1.num_cols {
				testing.expect(t, matrix_get(product1, r, c) == matrix_get(product2, r, c), fmt.tprintf(
					"expected same [%d, %d], got %d != %d\n", r, c, matrix_get(product1, r, c), matrix_get(product2, r, c))
				)
				if r == c {
					testing.expect(
						t,
						matrix_get(product1, r, c) == 1,
						fmt.tprintf(
							"expected 0, got matrix[%d, %d]=%d\n",
							r,
							c,
							matrix_get(product1, r, c),
						),
					)
				} else {
					testing.expect(
						t,
						matrix_get(product1, r, c) == 0,
						fmt.tprintf(
							"expected 0, got matrix[%d, %d]=%d\n",
							r,
							c,
							matrix_get(product1, r, c),
						),
					)
				}
			}
		}

	}
}

@(test)
test_matrix_binary_rep :: proc(t: ^testing.T) {
	field, _ := field_init(3)
	m, _ := matrix_init_cauchy(5, 3, field)
	defer matrix_deinit(m)

	for a in 0..<m.field.order {
		mat_a := field_matrix(m.field, a)
		for b in 0..< m.field.order {
			mat_b := field_matrix(m.field, b)
			sum := field_add(m.field, a, b)
			mat_sum := field_matrix(m.field, sum)
			for r in 0..< len(mat_a) {
				for c in 0..< len(mat_a[0]) {
					testing.expect(t, mat_sum[c][r] == field_add(m.field, mat_a[c][r], mat_b[c][r]), fmt.tprintf("expected [%d, %d]: %v, got %v", r, c, mat_sum, field_add(m.field, mat_a[c][r], mat_b[c][r])))
					
				}
			}
		}
	}
}

