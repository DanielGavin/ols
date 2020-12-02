package common

/*
    https://gist.github.com/jharler/7ee9a4d5b46e31f7f9399da49cfabe72
*/

import "core:mem"
import "core:fmt"
import "core:runtime"
import "core:sync"
import "core:log"

// ----------------------------------------------------------------------------------------------------

ThreadSafe_Allocator_Data :: struct {
    actual_allocator : mem.Allocator,
    mutex            : sync.Mutex,
}

// ----------------------------------------------------------------------------------------------------

threadsafe_allocator :: proc (allocator: mem.Allocator) -> mem.Allocator {
    data := new(ThreadSafe_Allocator_Data);
    data.actual_allocator = allocator;
    sync.mutex_init(&data.mutex);

    return mem.Allocator { procedure = threadsafe_allocator_proc, data = data};
}

// ----------------------------------------------------------------------------------------------------

threadsafe_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
                                  old_memory: rawptr, old_size: int, flags : u64 = 0, loc := #caller_location) -> rawptr {

    data := cast(^ThreadSafe_Allocator_Data)allocator_data;

    sync.mutex_lock(&data.mutex);
    defer sync.mutex_unlock(&data.mutex);

    return data.actual_allocator.procedure(data.actual_allocator.data, mode, size, alignment, old_memory, old_size, flags, loc);
}

// ----------------------------------------------------------------------------------------------------

Memleak_Allocator_Data :: struct {
    actual_allocator : mem.Allocator,
    allocations      : map[rawptr] Memleak_Entry,
    frees            : map[rawptr] Memleak_Entry,
    allocation_count : u32,
    unexpected_frees : u32,
    mutex            : sync.Mutex,
    track_frees      : bool,
}

// ----------------------------------------------------------------------------------------------------

Memleak_Entry :: struct {
    location : runtime.Source_Code_Location,
    size     : int,
    index    : u32,
}

// ----------------------------------------------------------------------------------------------------

memleak_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
                               old_memory: rawptr, old_size: int, flags : u64 = 0, loc := #caller_location) -> rawptr {

    memleak := cast(^Memleak_Allocator_Data)allocator_data;

    sync.mutex_lock(&memleak.mutex);
    defer sync.mutex_unlock(&memleak.mutex);

    if mode == .Free {
        if old_memory not_in memleak.allocations {
            if memleak.track_frees {
                if old_memory in memleak.frees {
                    fmt.println(fmt.tprintf("{0}({1}:{2}) {3} freed memory already freed by this memleak allocator", loc.file_path, loc.line, loc.column, loc.procedure));
                    free_loc := memleak.frees[old_memory].location;
                    fmt.println(fmt.tprintf("{0}({1}:{2}) {3} <<< freed here", loc.file_path, loc.line, loc.column, loc.procedure));
                }
                else {
                    fmt.println(fmt.tprintf("{0}({1}:{2}) {3} freed memory not allocated or previously freed by this memleak allocator", loc.file_path, loc.line, loc.column, loc.procedure));
                }
            }
            else {
                fmt.println(fmt.tprintf("{0}({1}:{2}) {3} freed memory not allocated by this memleak allocator", loc.file_path, loc.line, loc.column, loc.procedure));
            }
            memleak.unexpected_frees += 1;
            return nil;
        }
        else {
            //entry := &memleak.allocations[old_memory];
            delete_key(&memleak.allocations, old_memory);

            if memleak.track_frees {
                memleak.frees[old_memory] = Memleak_Entry {
                    location = loc,
                    size = size,
                    index = 0,
                };
            }
        }
    }

    result := memleak.actual_allocator.procedure(memleak.actual_allocator.data, mode, size, alignment, old_memory, old_size, flags, loc);

    if mode == .Resize && result != old_memory {
        delete_key(&memleak.allocations, old_memory);
    }

    if mode != .Free {
        // using a conditional breakpoint with memleak.allocation_count in the condition
        // can be very useful for inspecting the stack trace of a particular allocation

        memleak.allocations[result] = Memleak_Entry {
            location = loc,
            size = size,
            index = memleak.allocation_count,
        };

        memleak.allocation_count += 1;

        if memleak.track_frees {
            if result in memleak.frees {
                delete_key(&memleak.frees, result);
            }
        }
    }

    return result;
}

// ----------------------------------------------------------------------------------------------------

memleak_allocator :: proc (track_frees: bool) -> mem.Allocator {

    make([]byte, 1, context.temp_allocator); // so the temp allocation doesn't clutter our results

    data := new(Memleak_Allocator_Data);
    data.actual_allocator = context.allocator;
    data.allocations = make(map[rawptr]Memleak_Entry);

    if track_frees {
        data.track_frees = true;
        data.frees = make(map[rawptr]Memleak_Entry);
    }

    sync.mutex_init(&data.mutex);

    return mem.Allocator { procedure = memleak_allocator_proc, data = data};
}

// ----------------------------------------------------------------------------------------------------

memleak_detected_leaks :: proc() -> bool {
    if context.allocator.procedure == memleak_allocator_proc {
        memleak := cast(^Memleak_Allocator_Data)context.allocator.data;
        return len(memleak.allocations) > 0;
    }

    return false;
}

// ----------------------------------------------------------------------------------------------------

memleak_dump :: proc( memleak_alloc : mem.Allocator, dump_proc : proc(message:string, user_data:rawptr), user_data : rawptr) {
    memleak := cast(^Memleak_Allocator_Data)memleak_alloc.data;

    context.allocator = memleak.actual_allocator;

    // check for an ignore default_temp_allocator_proc allocations
    tmp_check := 0;
    for _, leak in &memleak.allocations {
        if leak.location.procedure == "default_temp_allocator_proc" {
            tmp_check += 1;
        }
    }


    dump_proc(fmt.tprintf("{0} memory leaks detected!", len(memleak.allocations) - tmp_check), user_data);
    dump_proc(fmt.tprintf("{0} unexpected frees", memleak.unexpected_frees), user_data);

    for _, leak in &memleak.allocations {
        if leak.location.procedure != "default_temp_allocator_proc" {
            dump_proc(fmt.tprintf("{0}({1}:{2}) {3} allocated {4} bytes [{5}]", leak.location.file_path, leak.location.line, leak.location.column, leak.location.procedure, leak.size, leak.index), user_data);
        }
    }

    context.allocator = mem.Allocator {procedure = memleak_allocator_proc, data = memleak};
}

// ----------------------------------------------------------------------------------------------------

log_dump :: proc(message:string, user_data:rawptr) {
    log.info(message);
}