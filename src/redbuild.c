#include "syscalls/syscalls.h"
#include "std/string.h"
#include "std/memory.h"
#include "data_struct/linked_list.h"

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#define _GNU_SOURCE
#include <dirent.h>
#include <pwd.h>

typedef enum { mac_os, linux_os, windows_os, redacted_os } os_name;

#if __linux
const os_name os = linux_os;
#elif _WIN32
const os_name os = windows_os;
#elif (__apple__)
const os_name os = mac_os;
#else 
const os_name os = redacted_os;
#endif

string link_libs;
string sources;
string includes;
string comp_flags;
string link_flags;
char *output; 

char *compiler = "";

const char *homedir;

typedef enum { dep_local, dep_framework, dep_system } dependency_type;

clinkedlist_t *sys_deps;
clinkedlist_t *comp_flags_list;
clinkedlist_t *link_flags_list;

typedef struct {
    dependency_type type;
    char *link;
    char *include;
    char *build;
    char *version;
    bool use_make;
} dependency_t; 

void traverse_directory(char *directory, bool recursive, string *str){
    DIR *dir;
    struct dirent *ent;
    if ((dir = opendir (directory)) == NULL) {
        printf("Failed to open path %s",directory);
        return;
    }
    
    while ((ent = readdir (dir)) != NULL) {
        if (recursive && ent->d_type == DT_DIR && !strstart(ent->d_name, ".")){
            string s = string_format("%s/%s",directory,ent->d_name);
            traverse_directory(s.data, true, str);
            string_free(s);
        }
        if (strend(ent->d_name, ".c") == 0)
            string_concat_inplace(str, string_format("%s/%s ", directory, ent->d_name));
    }
    closedir (dir);
}

void find_files(char *ext, string *str){
    char cwd[128];
    if (getcwd(cwd, sizeof(cwd)) == NULL){
        printf("NO PATH");
        return;
    }
    
    traverse_directory(cwd, true, str);
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

void add_compilation_flag(char *name){
    clinkedlist_push_front(comp_flags_list, name);
}

void add_linker_flag(char *name){
    clinkedlist_push_front(link_flags_list, name);
}

void common(){
    find_files(".c",&sources);
    sys_deps = clinkedlist_create();
    comp_flags_list = clinkedlist_create();
    link_flags_list = clinkedlist_create();

    if ((homedir = getenv("HOME")) == NULL) {
        homedir = getpwuid(getuid())->pw_dir;
    }

    include_self();
    add_local_dependency("/home/di/os/shared", "/home/di/os/shared/libshared.a", "/home/di/os/", true);
    add_local_dependency("/home/di/detour", "/home/di/detour/detour.a", "/home/di/detour/", true);
    
    link_libs = string_from_literal("/home/di/os/shared/libshared.a");
    output = "output";
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
        string_concat_inplace(&includes, string_format("-I%s ",dep->include));
    } 
    if (dep->link && strlen(dep->link)){
        string l = {};
        switch (dep->type) {
            case dep_local: l = string_format(" %s", dep->link); break;
            case dep_system: l = string_format(" -l%s",dep->link); break;
            case dep_framework: l = string_format(" -framework %s",dep->link); break;
        }
        if (l.data){
            string_concat_inplace(&link_libs, l);
        }
    } 
}

void process_comp_flags(void *data){
    char* flag = (char*)data;
    if (!comp_flags.data) comp_flags = string_format(" -D%s",flag);
    else string_concat_inplace(&comp_flags, string_format(" -D%s",flag));
}

void process_link_flags(void *data){
    char* flag = (char*)data;
    if (!link_flags.data) link_flags = string_format(" %s",flag);
    else string_concat_inplace(&link_flags, string_format(" %s",flag));
}

#define BUF_SIZE 1024
char buff[BUF_SIZE];

void comp(){
    if (!strlen(compiler)){
        printf("ERROR: Specify a compiler");
        return;
    }
    clinkedlist_for_each(sys_deps, process_dep);
    clinkedlist_for_each(comp_flags_list, process_comp_flags);
    clinkedlist_for_each(link_flags_list, process_link_flags);
    memset(buff, 0, BUF_SIZE);
    string_format_buf(buff, BUF_SIZE, "%s %s %s %s %s %s -o %s", compiler, comp_flags.data, link_flags.data, includes.data ? includes.data : "",sources.data ? sources.data : "",link_libs.data ? link_libs.data : "", output);
    printf("%s", buff);
    system(buff);
}

void cross_mod(){
    common();
    add_system_lib("c");
    add_system_lib("m");
    add_local_dependency("/home/di/raylib/src", "/home/di/raylib/src/libraylib.a", "", false);
    add_local_dependency("/home/di/redxlib", "/home/di/redxlib/redxlib.a", "/home/di/os/", true);
    add_compilation_flag("CROSS");
    switch (os) {
        case linux_os: add_linker_flag("-Wl,--start-group"); break;
        case windows_os: add_linker_flag("-fuse-ld=lld"); break;
        default: break;
    }
    
    compiler = "gcc";
    comp();
}

void red_mod(){
    common();
    compiler = "aarch64-none-elf-gcc";
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