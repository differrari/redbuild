#include "syscalls/syscalls.h"
#include "std/string.h"
#include "std/memory.h"
#include "data_struct/linked_list.h"
#include "std/string_slice.h"
#include "data/toml.h"
#include "data/csv.h"

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#define _GNU_SOURCE
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>

typedef enum { mac_os, linux_os, windows_os, redacted_os } os_name;

typedef enum { package_red, package_bin, package_lib } package_type;

char *output_name;

#if __linux
const os_name os = linux_os;
#elif _WIN32
const os_name os = windows_os;
#elif (__APPLE__)
const os_name os = mac_os;
#else 
const os_name os = redacted_os;
#endif

string link_libs;
string sources;
string ofiles;
string includes;
string preproc_flags;
string comp_flags;
string link_flags;

string output; 
package_type output_type;

char cwd[128];

char *compiler = "";

const char *homedir;

typedef enum { dep_local, dep_framework, dep_system } dependency_type;

typedef struct {
    string name;
    string output;
} comp_file;

clinkedlist_t *sys_deps;
clinkedlist_t *comp_files;
clinkedlist_t *preproc_flags_list;
clinkedlist_t *comp_flags_list;
clinkedlist_t *link_flags_list;
clinkedlist_t *ignore_list;

typedef struct {
    dependency_type type;
    char *link;
    char *include;
    char *build;
    char *version;
    bool use_make;
} dependency_t; 

typedef void (*dir_traverse)(const char *directory, const char* name);

void traverse_directory(char *directory, bool recursive, dir_traverse func){
    DIR *dir;
    struct dirent *ent;
    if ((dir = opendir (directory)) == NULL) {
        printf("Failed to open path %s",directory);
        return;
    }
    
    while ((ent = readdir (dir)) != NULL) {
        if (recursive && ent->d_type == DT_DIR && !strstart(ent->d_name, ".")){
            string s = string_format("%s/%s",directory,ent->d_name);
            traverse_directory(s.data, true, func);
            string_free(s);
        } else func(directory, ent->d_name);
    }
    closedir (dir);
}

static inline bool get_current_dir(){
    return strlen(cwd) || getcwd(cwd, sizeof(cwd));
}

int comp_str(void *a, void *b){
    return strcmp((char*)a,(char*)b);
}

void handle_files(const char *directory, const char *name){
    if (strend(name, ".c")) return;
    if (clinkedlist_find(ignore_list, (char*)name, comp_str)) {
        return;
    }
    comp_file *file = malloc(sizeof(comp_file));
    file->name = string_format("%s/%s",directory,name);
    file->output = string_format("%s/%v.o ", directory, make_string_slice(name,0,strlen(name)-2));
    clinkedlist_push_front(comp_files, file);
}

void find_files(char *ext, string *str){
    
    if (!get_current_dir()) { printf("No path"); return; }
    
    traverse_directory(cwd, true, handle_files);
}

void add_dependency(dependency_type type, char *include, char *link, char* build, bool use_make){
    dependency_t *dep = malloc(sizeof(dependency_t));
    dep->type = type;
    dep->include = include;
    dep->link = link;
    dep->build = build;
    dep->use_make = use_make;
    
    clinkedlist_push_front(sys_deps, dep);
}

void add_local_dependency(char *include, char *link, char* build, bool use_make){
    add_dependency(dep_local, include, link, build, use_make);
}

void add_system_lib(char *name){
    add_dependency(dep_system, "", name, "", false);
}

void add_system_framework(char *name){
    add_dependency(dep_framework, "", name, "", false);
}

void include_self(){
    add_dependency(dep_local, ".", "", "", false);   
}

void add_precomp_flag(char *name){
    clinkedlist_push_front(preproc_flags_list, name);
}

void add_compilation_flag(char *name){
    clinkedlist_push_front(comp_flags_list, name);
}

void add_linker_flag(char *name){
    clinkedlist_push_front(link_flags_list, name);
}

void prepare_output(){
    if (!get_current_dir()) { printf("No path"); return; }
    output_name = cwd;
    const char* next = cwd;
    do {
        output_name = (char*)next;
        next = seek_to(output_name, '/');
    } while (*next);
    
    switch (output_type) {
        case package_red: {
            string d = string_format("%s/%s.red",cwd,output_name);
            mkdir(d.data,0777);
            //TODO: create copy recursive functions for copying directories (ffs)
            string cmd1 = string_format("cp -rf package.info %s.red/package.info",output_name);
            string cmd2 = string_format("cp -rf resources %s.red/resources",output_name);
            printf("%s",cmd1.data);
            system(cmd1.data);
            printf("%s",cmd2.data);
            system(cmd2.data);
            string_free(d);
            string_free(cmd2);
            string_free(cmd1);
            output = string_format("%s.red/%s.elf",output_name, output_name);
        } break;
        case package_bin:
            output = string_format("%s.elf",output_name);
        break;
        case package_lib:
            output = string_format("%s.a",output_name);
        break;
    }
}

void on_ignore(string_slice ignore){
    clinkedlist_push_front(ignore_list, string_from_literal_length(ignore.data+1,ignore.length-2).data);
}

#define parse_toml(k,dest,func) if (strcmp_case(#k, key,true) == 0) dest.k = func(value,value_len)

void parse_config_kvp(string_slice key, string_slice value, void *context){
    if (strstart_case("build_type", key.data, true) == key.length){
        if (strstart_case("bin", value.data, true) == value.length){
            output_type = package_bin;
        }
        else if (strstart_case("pkg", value.data, true) == value.length){
            output_type = package_red;
        }
        else if (strstart_case("lib", value.data, true) == value.length){
            output_type = package_lib;
        } else printf("Unexpected output type %v",value);
        printf("Output type %v",value);
    }
    
    if (strstart_case("ignore", key.data, true) == key.length){
        read_csv(value, on_ignore);
    }
}

void common(){
    sys_deps = clinkedlist_create();
    preproc_flags_list = clinkedlist_create();
    comp_flags_list = clinkedlist_create();
    link_flags_list = clinkedlist_create();
    comp_files = clinkedlist_create();
    ignore_list = clinkedlist_create();
    
    file fd = {};
    
    if (!get_current_dir()) { printf("No path"); return; }
    
    string s = string_format("%s/build.config",cwd);
    
    char *config_file = read_full_file(s.data);
    
    read_toml(config_file, parse_config_kvp, 0);

    if ((homedir = getenv("HOME")) == NULL) {
        homedir = getpwuid(getuid())->pw_dir;
    }
    find_files(".c",&sources);

    include_self();
    add_local_dependency("~/detour", "~/detour/detour.a", "~/detour/", true);
    
    add_compilation_flag("no-format-invalid-specifier");
    
    prepare_output();
}

void cleanup(){
    string_free(link_libs);
    string_free(sources);
    string_free(includes);
}

void process_dep(void *data){
    dependency_t *dep = (dependency_t*)data;
    if (!dep) return;
    
    if (dep->include && strlen(dep->include)){
        string s = string_replace_character(dep->include, '~', (char*)homedir);
        string sf = string_format("-I%s ",s.data);
        string_concat_inplace(&includes, sf);
        string_free(s);
        string_free(sf);
    } 
    if (dep->link && strlen(dep->link)){
        string l = {};
        string s = string_replace_character(dep->link, '~', (char*)homedir);
        switch (dep->type) {
            case dep_local: l = string_format(" %s", s.data); break;
            case dep_system: l = string_format(" -l%s",s.data); break;
            case dep_framework: l = string_format(" -framework %s",s.data); break;
        }
        if (l.data){
            string_concat_inplace(&link_libs, l);
            string_free(l);
        }
        string_free(s);
    } 
}

void process_preproc_flags(void *data){
    char* flag = (char*)data;
    if (!preproc_flags.data) preproc_flags = string_format(" -D%s",flag);
    else string_concat_inplace(&preproc_flags, string_format(" -D%s",flag));
}

void process_comp_flags(void *data){
    char* flag = (char*)data;
    if (!preproc_flags.data) preproc_flags = string_format(" -W%s",flag);
    else string_concat_inplace(&preproc_flags, string_format(" -W%s",flag));
}

void process_link_flags(void *data){
    char* flag = (char*)data;
    if (!link_flags.data) link_flags = string_format(" %s",flag);
    else string_concat_inplace(&link_flags, string_format(" %s",flag));
}

void process_comp_files(void *data){
    comp_file *file = (comp_file*)data;
    if (!sources.data) sources = string_format(" %s",file->name);
    else string_concat_inplace(&sources, string_format(" %s",file->name));
}

void process_out_files(void *data){
    comp_file *file = (comp_file*)data;
    if (!ofiles.data) ofiles = string_format(" %s",file->output);
    else string_concat_inplace(&ofiles, string_format(" %s",file->output));
}

#define BUF_SIZE 1024
char buff[BUF_SIZE];

void lib_compile_individual(void *data){
    comp_file *file = (comp_file*)data;
    memset(buff, 0, BUF_SIZE);
    string_format_buf(buff, BUF_SIZE, "%s %s %s %s -c %s -o %s", compiler, preproc_flags.data ? preproc_flags.data : "", comp_flags.data ? comp_flags.data : "", includes.data ? includes.data : "",file->name.data, file->output.data);
    printf("%s",buff);
    system(buff);
}

void comp(){
    if (!strlen(compiler)){
        printf("ERROR: Specify a compiler");
        return;
    }
    clinkedlist_for_each(sys_deps, process_dep);
    clinkedlist_for_each(preproc_flags_list, process_preproc_flags);
    clinkedlist_for_each(comp_flags_list, process_comp_flags);
    clinkedlist_for_each(link_flags_list, process_link_flags);
    memset(buff, 0, BUF_SIZE);
    
    if (output_type == package_lib){
        clinkedlist_for_each(comp_files, lib_compile_individual);
        memset(buff, 0, BUF_SIZE);
        clinkedlist_for_each(comp_files, process_out_files);
        string_format_buf(buff, BUF_SIZE, "ar rcs %s %s",output.data,ofiles.data);
        printf("%s",buff);
        system(buff);
    } else {
        clinkedlist_for_each(comp_files, process_comp_files);
        string_format_buf(buff, BUF_SIZE, "%s %s %s %s %s %s %s -o %s", compiler, preproc_flags.data ? preproc_flags.data : "", comp_flags.data ? comp_flags.data : "", link_flags.data ? link_flags.data : "", includes.data ? includes.data : "",sources.data ? sources.data : "",link_libs.data ? link_libs.data : "", output.data);
        printf("%s",buff);
        system(buff);
    }
}

void cross_mod(){
    common();
    add_system_lib("c");
    add_system_lib("m");
    add_local_dependency("~/os/shared", "~/os/shared/clibshared.a", "~/os/", true);
    add_local_dependency("~/raylib/src", "~/raylib/src/libraylib.a", "", false);
    add_local_dependency("~/redxlib", "~/redxlib/redxlib.a", "~/os/", true);
    add_precomp_flag("CROSS");
    switch (os) {
        case linux_os: add_linker_flag("-Wl,--start-group"); break;
        case windows_os: add_linker_flag("-fuse-ld=lld"); break;
        case mac_os: {
            add_system_framework("Cocoa");
            add_system_framework("IOKit");
            add_system_framework("CoreVideo");
            add_system_framework("CoreFoundation");
        } break;
        default: break;
    }
    
    compiler = "gcc";
    comp();
}

void red_mod(){
    common();
    compiler = "aarch64-none-elf-gcc";
    add_local_dependency("~/os/shared", "~/os/shared/libshared.a", "~/os/", true);
    add_linker_flag("-Wl,-emain");
    comp();
}

void clean_mod(){
    printf("Running %s",__func__);
}

void dump_mod(){
    printf("Running %s",__func__);
}

int main(int argc, char *argv[]){
    
    printf("Current choice %s",argv[1]);
    
    char *command = argv[1];//TODO: redacted currently does not have the executable at 0
    
    if (strcmp(command,"cross") == 0){
        cross_mod();
    }
    
    if (strcmp(command,"run") == 0){
        red_mod();
    }
    
    if (strcmp(command,"clean") == 0){
        clean_mod();
    }
    
    if (strcmp(command,"dump") == 0){
        dump_mod();
    }
    
    return 0;
}