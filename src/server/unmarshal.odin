package server

import "base:runtime"

import "core:encoding/json"
import "core:strings"
import "core:mem"
import "core:fmt"

/*
	Right now union handling is type specific so you can only have one struct type, int type, etc.
*/

unmarshal :: proc(
	json_value: json.Value,
	v: any,
	allocator: mem.Allocator,
) -> json.Marshal_Error {

	using runtime

	if v == nil {
		return nil
	}

	if json_value == nil {
		return nil
	}

	type_info := type_info_base(type_info_of(v.id))

	#partial switch j in json_value {
	case json.Object:
		#partial switch variant in type_info.variant {
		case Type_Info_Struct:
			for field, i in variant.names {
				a := any{
					rawptr(uintptr(v.data) + uintptr(variant.offsets[i])),
					variant.types[i].id,
				}

				//TEMP most likely have to rewrite the entire unmarshal using tags instead, because i sometimes have to support names like 'context', which can't be written like that
				if field[len(field) - 1] == '_' {
					if ret := unmarshal(
						j[field[:len(field) - 1]],
						a,
						allocator,
					); ret != nil {
						return ret
					}
				} else {
					if ret := unmarshal(j[field], a, allocator); ret != nil {
						return ret
					}
				}


			}

		case Type_Info_Union:
			tag_ptr := uintptr(v.data) + variant.tag_offset
			tag_any := any{rawptr(tag_ptr), variant.tag_type.id}

			not_optional := 1

			mem.copy(
				cast(rawptr)tag_ptr,
				&not_optional,
				size_of(variant.tag_type),
			)

			id := variant.variants[0].id

			unmarshal(json_value, any{v.data, id}, allocator)
		}
	case json.Array:
		#partial switch variant in type_info.variant {
		case Type_Info_Dynamic_Array:
			array := (^mem.Raw_Dynamic_Array)(v.data)
			if array.data == nil {
				array.data = mem.alloc(
					len(j) * variant.elem_size,
					variant.elem.align,
					allocator,
				) or_else panic("OOM")
				array.len = len(j)
				array.cap = len(j)
				array.allocator = allocator
			} else {
				return .Unsupported_Type
			}

			for i in 0 ..< array.len {
				a := any{
					rawptr(
						uintptr(array.data) + uintptr(variant.elem_size * i),
					),
					variant.elem.id,
				}

				if ret := unmarshal(j[i], a, allocator); ret != nil {
					return ret
				}
			}

		case:
			return .Unsupported_Type
		}
	case json.String:
		#partial switch variant in type_info.variant {
		case Type_Info_String:
			str := (^string)(v.data)
			str^ = strings.clone(j, allocator)

		case Type_Info_Enum:
			for name, i in variant.names {

				lower_name := strings.to_lower(name, allocator)
				lower_j := strings.to_lower(string(j), allocator)

				if lower_name == lower_j {
					mem.copy(v.data, &variant.values[i], size_of(variant.base))
				}

				delete(lower_name, allocator)
				delete(lower_j, allocator)
			}
		}
	case json.Integer:
		#partial switch variant in &type_info.variant {
		case Type_Info_Integer:
			switch type_info.size {
			case 8:
				tmp := i64(j)
				mem.copy(v.data, &tmp, type_info.size)

			case 4:
				tmp := i32(j)
				mem.copy(v.data, &tmp, type_info.size)

			case 2:
				tmp := i16(j)
				mem.copy(v.data, &tmp, type_info.size)

			case 1:
				tmp := i8(j)
				mem.copy(v.data, &tmp, type_info.size)
			case:
				return .Unsupported_Type
			}
		case Type_Info_Union:
			tag_ptr := uintptr(v.data) + variant.tag_offset
		}
	case json.Float:
		if _, ok := type_info.variant.(Type_Info_Float); ok {
			switch type_info.size {
			case 8:
				tmp := f64(j)
				mem.copy(v.data, &tmp, type_info.size)
			case 4:
				tmp := f32(j)
				mem.copy(v.data, &tmp, type_info.size)
			case:
				return .Unsupported_Type
			}
		}
	case json.Null:
	case json.Boolean:
		#partial switch variant in &type_info.variant {
		case Type_Info_Boolean:
			tmp := bool(j)
			mem.copy(v.data, &tmp, type_info.size)
		case Type_Info_Union:
			tag_ptr := uintptr(v.data) + variant.tag_offset
			tag_any := any{rawptr(tag_ptr), variant.tag_type.id}

			not_optional := 1

			mem.copy(
				cast(rawptr)tag_ptr,
				&not_optional,
				size_of(variant.tag_type),
			)

			id := variant.variants[0].id

			unmarshal(json_value, any{v.data, id}, allocator)
		}
	case:
		return .Unsupported_Type
	}

	return nil
}
