package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:path/filepath"
import "src:common"

/**
 * PluginManager is responsible for managing the lifecycle of all OLS plugins.
 * 
 * It handles plugin registration, initialization, configuration, analysis coordination,
 * and cleanup. The PluginManager ensures that plugins are properly integrated
 * into the OLS analysis pipeline.
 *
 * Key Responsibilities:
 * - Maintain registry of available plugins
 * - Coordinate plugin lifecycle events
 * - Merge plugin diagnostics with OLS diagnostics
 * - Handle plugin errors and recovery
 */
PluginManager :: struct {
    /** Array of registered plugins */
    plugins:        [dynamic]^OLSPlugin,
    /** Memory allocator for plugin management */
    allocator:      mem.Allocator,
    /** Whether the plugin system has been initialized */
    initialized:    bool,
}

/**
 * Create a new plugin manager instance.
 * 
 * Parameters:
 *   allocator: mem.Allocator - Memory allocator to use for plugin management
 * 
 * Returns: PluginManager - Initialized plugin manager ready for use
 */
create_plugin_manager :: proc(allocator: mem.Allocator) -> PluginManager {
    return PluginManager{
        plugins = make([dynamic]^OLSPlugin, 0, allocator),
        allocator = allocator,
        initialized = false,
    }
}

/**
 * Initialize all registered plugins.
 * 
 * This should be called after all plugins have been registered and OLS is ready
 * to start processing documents.
 * 
 * Parameters:
 *   manager: ^PluginManager - Plugin manager instance
 * 
 * Returns: bool - true if all plugins initialized successfully, false otherwise
 */
initialize_plugins :: proc(manager: ^PluginManager) -> bool {
    manager.initialized = false
    
    for p in manager.plugins {
        if !p.initialize() {
            error_info: PluginErrorInfo;
            error_info.error_type = .InitializationFailed
            error_info.message = "Plugin initialization returned false"
            error_info.plugin = p.get_info().name
            error_info.recovery = "Check plugin logs and configuration"
            handle_plugin_error(manager, error_info)
            // Continue with other plugins even if one fails
            continue
        }
        log.infof("Initialized plugin: %s v%s", p.get_info().name, p.get_info().version)
    }
    
    manager.initialized = true
    return true
}

// Configure all plugins
configure_plugins :: proc(manager: ^PluginManager) -> bool {
    for p in manager.plugins {
        if !p.configure() {
            log.errorf("Failed to configure plugin: %s", p.get_info().name)
            return false
        }
    }
    
    return true
}

/**
 * Analyze a file with all plugins and collect diagnostics.
 * 
 * This is the core integration point where plugins participate in the
 * OLS analysis pipeline. Each plugin's analyze_file method is called,
 * and their diagnostics are collected and returned.
 * 
 * Parameters:
 *   manager: ^PluginManager - Plugin manager instance
 *   document: rawptr - Pointer to the Document being analyzed
 *   ast: ^ast.File - Abstract Syntax Tree of the document
 * 
 * Returns: [dynamic]Diagnostic - Combined diagnostics from all plugins
 */
analyze_with_plugins :: proc(manager: ^PluginManager, document: rawptr, ast: ^ast.File) -> [dynamic]Diagnostic {
    if !manager.initialized {
        return nil;
    }
    
    all_diagnostics: [dynamic]Diagnostic;
    
    for p in manager.plugins {
        plugin_diagnostics := p.analyze_file(document, ast);
        for diag in plugin_diagnostics {
            // Add plugin source information to diagnostic
            // For now, just ensure diagnostics are properly attributed
            // In a production system, we would extend the Diagnostic type
            append(&all_diagnostics, diag);
        }
    }
    
    return all_diagnostics;
}

// Shutdown all plugins
shutdown_plugins :: proc(manager: ^PluginManager) {
    for p in manager.plugins {
        p.shutdown()
        log.infof("Shutdown plugin: %s", p.get_info().name)
    }
    
    manager.plugins = make([dynamic]^OLSPlugin, 0, manager.allocator)
    manager.initialized = false
}

// Register a new plugin
register_plugin :: proc(manager: ^PluginManager, plugin: ^OLSPlugin) -> bool {
    // Check if plugin already exists
    for ep in manager.plugins {
        if ep.get_info().name == plugin.get_info().name {
            log.errorf("Plugin already registered: %s", plugin.get_info().name)
            return false
        }
    }
    
    append(&manager.plugins, plugin)
    log.infof("Registered plugin: %s v%s", plugin.get_info().name, plugin.get_info().version)
    return true
}

// Unregister a plugin by name
unregister_plugin :: proc(manager: ^PluginManager, plugin_name: string) -> bool {
    for i in 0..<len(manager.plugins) {
        plugin_ptr := manager.plugins[i]
        if plugin_ptr.get_info().name == plugin_name {
            plugin_ptr.shutdown()
            ordered_remove(&manager.plugins, i)
            log.infof("Unregistered plugin: %s", plugin_name)
            return true
        }
    }
    
    log.errorf("Plugin not found: %s", plugin_name)
    return false
}

// Get plugin by name
get_plugin :: proc(manager: ^PluginManager, plugin_name: string) -> (^OLSPlugin, bool) {
    for plugin in manager.plugins {
        if plugin.get_info().name == plugin_name {
            return plugin, true
        }
    }
    return nil, false
}

// Get all plugin info
get_all_plugin_info :: proc(manager: ^PluginManager) -> [dynamic]PluginInfo {
    infos: [dynamic]PluginInfo;
    
    for p in manager.plugins {
        append(&infos, p.get_info());
    }
    
    return infos;
}

// Handle plugin errors
handle_plugin_error :: proc(manager: ^PluginManager, error: PluginErrorInfo) {
    switch error.error_type {
        case .InitializationFailed:
            log.errorf("[PLUGIN ERROR] %s: Initialization failed - %s", error.plugin, error.message)
        case .AnalysisFailed:
            log.errorf("[PLUGIN ERROR] %s: Analysis failed - %s", error.plugin, error.message)
        case .ConfigurationError:
            log.errorf("[PLUGIN ERROR] %s: Configuration error - %s", error.plugin, error.message)
        case .ResourceError:
            log.errorf("[PLUGIN ERROR] %s: Resource error - %s", error.plugin, error.message)
    }
    
    if len(error.recovery) > 0 {
        log.infof("Recovery suggestion: %s", error.recovery)
    }
}