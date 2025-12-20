#include "syscalls/syscalls.h"
#include "std/string.h"
#include "data_struct/linked_list.h"

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <dirent.h>
#include <pwd.h>

string link_libs;
string sources;
string includes;
char *output; 

char *compiler = "";

const char *homedir;

typedef enum { dep_local, dep_framework, dep_system } dependency_type;

clinkedlist_t *sys_deps;

typedef struct {
    dependency_type type;
    char *link;
    char *include;
    char *build;
    char *version;
    bool use_make;
} dependency_t; 

void find_files(char *ext, string *str){
    char cwd[128];
    if (getcwd(cwd, sizeof(cwd)) == NULL){
        printf("NO PATH");
        return;
    }
    
    DIR *dir;
    struct dirent *ent;
    if ((dir = opendir (cwd)) == NULL) {
        printf("Failed to open path");
        return;
    }
    
    while ((ent = readdir (dir)) != NULL) {
        if (strend(ent->d_name, ".c") == 0)
            string_concat_inplace(str, string_format("%s ", ent->d_name));
    }
    closedir (dir);
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

void common(){
    find_files(".c",&sources);
    sys_deps = clinkedlist_create();

    if ((homedir = getenv("HOME")) == NULL) {
        homedir = getpwuid(getuid())->pw_dir;
    }

    add_local_dependency("/home/di/os/shared", "/home/di/os/shared/libshared.a", "/home/di/os/", true);
    
    link_libs = string_from_literal("/home/di/os/shared/libshared.a");
    output = "build2.r";
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

void comp(){
    if (!strlen(compiler)){
        printf("ERROR: Specify a compiler");
        return;
    }
    clinkedlist_for_each(sys_deps, process_dep);
    string s = string_format("%s %s %s %s -o %s",compiler, includes.data ? includes.data : "",sources.data ? sources.data : "",link_libs.data ? link_libs.data : "",output);
    printf(s.data);
    system(s.data);
    string_free(s);
}

void cross_mod(){
    common();
    add_system_lib("c");
    add_system_lib("m");
    add_local_dependency("/home/di/raylib/src", "/home/di/raylib/src/libraylib.a", "", false);
    add_local_dependency("/home/di/redxlib", "/home/di/redxlib/redxlib.a", "/home/di/os/", true);
    compiler = "gcc";
    comp();
}

void red_mod(){
    common();
    compiler = "aarch64-none-elf-gcc";
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