package tests

import "core:os"
import "core:path/filepath"
import "core:testing"

import "src:common"
import "src:server"

@(test)
append_packages_skip_directories :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "ols-packages-*", context.temp_allocator)
	if !testing.expectf(t, err == nil, "failed to create temporary directory: %v", err) {
		return
	}
	defer os.remove_all(root)
	root, err = os.get_absolute_path(root, context.temp_allocator)
	if !testing.expectf(t, err == nil, "failed to resolve temporary directory: %v", err) {
		return
	}

	included, _ := filepath.join({root, "included"}, context.temp_allocator)
	excluded, _ := filepath.join({root, "excluded"}, context.temp_allocator)
	hidden, _ := filepath.join({root, ".hidden"}, context.temp_allocator)
	if !testing.expect(t, os.make_directory(included) == nil) ||
	   !testing.expect(t, os.make_directory(excluded) == nil) ||
	   !testing.expect(t, os.make_directory(hidden) == nil) {
		return
	}

	included_file, _ := filepath.join({included, "included.odin"}, context.temp_allocator)
	excluded_file, _ := filepath.join({excluded, "excluded.odin"}, context.temp_allocator)
	hidden_file, _ := filepath.join({hidden, "hidden.odin"}, context.temp_allocator)
	if !testing.expect(t, os.write_entire_file(included_file, "package included") == nil) ||
	   !testing.expect(t, os.write_entire_file(excluded_file, "package excluded") == nil) ||
	   !testing.expect(t, os.write_entire_file(hidden_file, "package hidden") == nil) {
		return
	}

	skip := make(map[string]struct{}, context.temp_allocator)
	skip[excluded] = {}

	packages := make([dynamic]string, context.temp_allocator)
	server.append_packages(root, &packages, skip, context.temp_allocator, skip_hidden = true)

	testing.expect_value(t, len(packages), 1)
	if len(packages) == 1 {
		testing.expect_value(t, packages[0], included)
	}

	clear(&packages)
	server.append_packages(root, &packages, skip, context.temp_allocator, skip_hidden = false)
	testing.expect_value(t, len(packages), 2)

	skip[root] = {}
	clear(&packages)
	server.append_packages(root, &packages, skip, context.temp_allocator, skip_hidden = false)
	testing.expect_value(t, len(packages), 0)
}

@(test)
refresh_package_aliases_when_hidden_path_setting_changes :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "ols-aliases-*", context.temp_allocator)
	if !testing.expectf(t, err == nil, "failed to create temporary directory: %v", err) {
		return
	}
	defer os.remove_all(root)
	root, err = os.get_absolute_path(root, context.temp_allocator)
	if !testing.expectf(t, err == nil, "failed to resolve temporary directory: %v", err) {
		return
	}

	included, _ := filepath.join({root, "included"}, context.temp_allocator)
	hidden, _ := filepath.join({root, ".hidden"}, context.temp_allocator)
	if !testing.expect(t, os.make_directory(included) == nil) ||
	   !testing.expect(t, os.make_directory(hidden) == nil) {
		return
	}

	included_file, _ := filepath.join({included, "included.odin"}, context.temp_allocator)
	hidden_file, _ := filepath.join({hidden, "hidden.odin"}, context.temp_allocator)
	if !testing.expect(t, os.write_entire_file(included_file, "package included") == nil) ||
	   !testing.expect(t, os.write_entire_file(hidden_file, "package hidden") == nil) {
		return
	}

	config: common.Config
	config.collections = make(map[string]string, context.temp_allocator)
	config.collections["test"] = root
	config.enable_auto_import_skip_hidden_paths = false

	previous_aliases := server.build_cache.pkg_aliases
	server.build_cache.pkg_aliases = make(map[string][dynamic]string, context.temp_allocator)
	defer {
		server.clear_all_package_aliases()
		delete(server.build_cache.pkg_aliases)
		server.build_cache.pkg_aliases = previous_aliases
	}

	server.find_all_package_aliases(&config)
	aliases := server.build_cache.pkg_aliases["test"]
	testing.expect_value(t, len(aliases), 2)

	previous_value := config.enable_auto_import_skip_hidden_paths
	config.enable_auto_import_skip_hidden_paths = true
	testing.expect(
		t,
		server.refresh_package_aliases_if_hidden_paths_changed(previous_value, &config),
	)

	aliases = server.build_cache.pkg_aliases["test"]
	testing.expect_value(t, len(aliases), 1)
	if len(aliases) == 1 {
		testing.expect_value(t, aliases[0], "included")
	}

	testing.expect(
		t,
		!server.refresh_package_aliases_if_hidden_paths_changed(config.enable_auto_import_skip_hidden_paths, &config),
	)
}
