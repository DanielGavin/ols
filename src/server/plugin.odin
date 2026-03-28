package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "src:common"

/**
 * OLSPlugin represents the interface that all OLS plugins must implement.
 * 
 * The plugin system allows for extensible functionality in the Odin Language Server,
 * enabling features like linting, formatting, and other code analysis tools
 * to be developed as separate plugins.
 * 
 * Plugin Lifecycle:
 * 1. Registration: Plugin is registered with the PluginManager
 * 2. Initialization: initialize() is called when OLS starts
 * 3. Configuration: configure() is called when settings change
 * 4. Analysis: analyze_file() is called during document processing
 * 5. Shutdown: shutdown() is called when OLS exits
 */
OLSPlugin :: struct {
    /**
     * Initialize the plugin with required resources.
     * This is called once when the plugin is first loaded.
     * 
     * Returns: bool - true if initialization succeeded, false otherwise
     */
    initialize: proc() -> bool,
    
    /**
     * Analyze a file and return diagnostics.
     * This is called whenever a document is opened or changed.
     * 
     * Parameters:
     *   document: rawptr - Pointer to the Document being analyzed
     *   ast: ^ast.File - Abstract Syntax Tree of the document
     * 
     * Returns: [dynamic]Diagnostic - Array of diagnostics found during analysis
     */
    analyze_file: proc(document: rawptr, ast: ^ast.File) -> [dynamic]Diagnostic,
    
    /**
     * Handle configuration changes.
     * This is called when the plugin's configuration is updated.
     * 
     * Returns: bool - true if configuration was handled successfully, false otherwise
     */
    configure: proc() -> bool,
    
    /**
     * Cleanup plugin resources.
     * This is called when OLS is shutting down.
     */
    shutdown: proc(),
    
    /**
     * Get plugin metadata.
     * 
     * Returns: PluginInfo - Information about the plugin
     */
    get_info: proc() -> PluginInfo,
}

/**
 * PluginInfo contains metadata about a plugin.
 * This information is used for logging, debugging, and plugin management.
 */
PluginInfo :: struct {
    /** Plugin name - unique identifier for the plugin */
    name:        string,
    /** Plugin version - semantic version string */
    version:     string,
    /** Plugin description - brief description of what the plugin does */
    description: string,
    /** Plugin author - name of the plugin author/maintainer */
    author:      string,
}

/**
 * PluginDiagnostic extends the standard LSP Diagnostic with additional fields
 * specific to odin-lint and other analysis plugins.
 * 
 * This allows plugins to provide richer diagnostic information including
 * rule identifiers, fix suggestions, and quick fix actions.
 */
PluginDiagnostic :: struct {
    // Standard LSP fields
    /** Diagnostic range in the source file */
    range:    common.Range,
    /** Severity level (Error, Warning, Information, Hint) */
    severity: DiagnosticSeverity,
    /** Diagnostic code/identifier */
    code:     string,
    /** Source of the diagnostic (plugin name) */
    source:   string,
    /** Human-readable diagnostic message */
    message:  string,
    
    // odin-lint specific extensions
    /** Rule identifier (e.g., "C001") */
    rule_id:          string,
    /** Suggested fix for the issue */
    fix_suggestion:   string,
    /** URI to documentation about this rule */
    documentation_uri: string,
    
    // Context for quick fixes
    /** Optional quick fix action */
    quick_fix:        ^QuickFix,
}

/**
 * QuickFix represents a code action that can automatically fix a diagnostic.
 * These are presented to the user as "Quick Fix" options in the editor.
 */
QuickFix :: struct {
    /** Display title for the quick fix */
    title:      string,
    /** Workspace edit that implements the fix */
    edit:       ^WorkspaceEdit,
    /** Whether this is the preferred fix */
    is_preferred: bool,
}

/**
 * PluginError categorizes different types of plugin failures.
 * Used for error handling and recovery in the plugin system.
 */
PluginError :: enum {
    /** Plugin failed to initialize properly */
    InitializationFailed,
    /** Plugin analysis encountered an error */
    AnalysisFailed,
    /** Plugin configuration is invalid */
    ConfigurationError,
    /** Plugin encountered a resource error (memory, file access, etc.) */
    ResourceError,
}

/**
 * PluginErrorInfo provides detailed information about a plugin error.
 * Used for logging, debugging, and recovery suggestions.
 */
PluginErrorInfo :: struct {
    /** Type of error that occurred */
    error_type: PluginError,
    /** Human-readable error message */
    message:    string,
    /** Name of the plugin that failed */
    plugin:     string,
    /** Optional recovery suggestion */
    recovery:   string,
}