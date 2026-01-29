#pragma once

#include "../redlib/types.h"

typedef enum {
    target_redacted,
    target_linux,
    target_mac,
    target_windows,
    target_native,
} target;

typedef enum { dep_local, dep_framework, dep_system } dependency_type;

typedef struct {
    dependency_type type;
    char *link;
    char *include;
    char *build;
    char *version;
    bool use_make;
} dependency_t; 

typedef enum { package_red, package_bin, package_lib } package_type;

void set_target(target t);
void set_package_type(package_type type);
void set_name(const char *out_name);

void rebuild_self();
void new_module(const char *name);
bool source(const char *name);
bool compile();
bool gen_compile_commands();
bool cred_compile();
bool quick_cred(const char *input_file, const char *output_file);
int run();
void install(const char *location);
bool make_run(const char *directory, const char *command);

void add_dependency(dependency_type type, char *include, char *link, char* build, bool use_make);
void add_local_dependency(char *include, char *link, char* build, bool use_make);
void add_system_lib(char *name);
void add_system_framework(char *name);
void include_self();
void add_precomp_flag(char *name);
void add_compilation_flag(char *name);
void add_linker_flag(char *name, bool back);

bool ignore_source(const char *name);
bool source_all(const char *ext);