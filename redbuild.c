#include "redbuild.h"
#include "../redlib/data/struct/linked_list.h"
#include "../redlib/std/string.h"
#include "../redlib/std/string_slice.h"
#include "../redlib/syscalls/syscalls.h"
#include "files/helpers.h"
#include "files/buffer.h"

clinkedlist_t *compile_list;
clinkedlist_t *preproc_flags_list;
clinkedlist_t *comp_flags_list;
clinkedlist_t *link_flags_list_f;
clinkedlist_t *link_flags_list_b;
clinkedlist_t *includes;
clinkedlist_t *link_libs;
clinkedlist_t *ignore_list;
clinkedlist_t *out_files;

target selected_target;

char *output_name;
const char *homedir;
string output;

char *chosen_compiler = 0;

static target compilation_target;
static package_type pkg_type;

buffer buf;
buffer ccbuf;
char *extension;

// #define DEBUG
#ifdef DEBUG
#define redbuild_debug(fmt, ...) print(fmt, ##__VA_ARGS__)
#else 
#define redbuild_debug(fmt, ...)
#endif

#if __linux
#define native_target target_linux
#elif _WIN32
#define native_target target_windows
#elif (__APPLE__)
#define native_target target_mac
#else 
#define native_target target_redacted
#endif

void free_strings(void *data){
    string *s = (string*)data;
    string_free(*s);
}

void free_deps(void *data){
    dependency_t *dep = (dependency_t*)data;
    free_sized(dep, sizeof(dependency_t));
}

void push_lit(clinkedlist_t *list, const char* lit){
    string *s = malloc(sizeof(string));
    *s = string_from_literal(lit);
    clinkedlist_push(list, s);
}

void cross_mod(){
    redbuild_debug("Native platform setup");
    add_system_lib("c");
    add_system_lib("m");
    add_local_dependency("~/redlib", "~/redlib/clibshared.a", "~/redlib", true);
    add_local_dependency("~/raylib/src", "~/raylib/src/libraylib.a", "", false);
    add_precomp_flag("CROSS");
    redbuild_debug("Common platform setup done");
    switch (compilation_target) {
        case target_linux: add_linker_flag("-Wl,--start-group", false); add_linker_flag("-Wl,--end-group", true);break;
        case target_windows: add_linker_flag("-fuse-ld=lld", false); break;
        case target_mac: {
            add_system_framework("Cocoa");
            add_system_framework("IOKit");
            add_system_framework("CoreVideo");
            add_system_framework("CoreFoundation");
        } break;
        default: break;
    }
    redbuild_debug("Platform specific setup done. Selecting compiler");
    chosen_compiler = "gcc";
    redbuild_debug("Compiler selected");
    redbuild_debug("Compiler %s",chosen_compiler);
}

void red_mod(){
    chosen_compiler = "aarch64-none-elf-gcc";
    add_local_dependency("~/redlib", "~/redlib/libshared.a", "~/os/", true);
    add_linker_flag("-Wl,-emain",false);
    add_linker_flag("-ffreestanding", false);
    add_linker_flag("-nostdlib", false);
}

void common(){
    redbuild_debug("Getting home dir");
    homedir = gethomedir();
    redbuild_debug("Home dir %s",homedir);
    
    include_self();
    
    add_compilation_flag("no-format-invalid-specifier");
    add_compilation_flag("no-format-extra-args");
}

void set_target(target t){
    if (t == target_native)
        compilation_target = native_target;
    else 
        compilation_target = t;
    redbuild_debug("Target type %i",compilation_target);
}

void set_name(const char *out_name){
    output_name = (char*)out_name;
}

void prepare_output(){
    if (!output_name) {
        print("No output name specified");
        return;
    }
    char *cwd = get_current_dir();
    switch (pkg_type) {
        case package_red: {
            //TODO: %s feel dangerous here
            string d = string_format("mkdir -p %s/%s.red",cwd,output_name);
            printf("Making %s/%s.red",cwd,output_name);
            system(d.data);
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
    redbuild_debug("Output environment ready");
}

void set_package_type(package_type type){
    pkg_type = type;
    redbuild_debug("Package type %i",pkg_type);
}

void new_module(const char *name){
    printf("Compiling target %s",name);
    if (compile_list){
        if (compile_list->length) clinkedlist_for_each(compile_list, free_strings);
        clinkedlist_destroy(compile_list);
    }
    
    if (preproc_flags_list){
        if (preproc_flags_list->length) clinkedlist_for_each(preproc_flags_list, free_strings);
        clinkedlist_destroy(preproc_flags_list);
    }
    
    if (includes){
        if (includes->length) clinkedlist_for_each(includes, free_strings);
        clinkedlist_destroy(includes);
    }
    
    if (link_libs){
        if (link_libs->length) clinkedlist_for_each(link_libs, free_strings);
        clinkedlist_destroy(link_libs);
    }
    
    if (comp_flags_list){
        if (comp_flags_list->length) clinkedlist_for_each(comp_flags_list, free_strings);
        clinkedlist_destroy(comp_flags_list);
    }
    
    if (link_flags_list_f){
        if (link_flags_list_f->length) clinkedlist_for_each(link_flags_list_f, free_strings);
        clinkedlist_destroy(link_flags_list_f);
    }
    
    if (link_flags_list_b){
        if (link_flags_list_b->length) clinkedlist_for_each(link_flags_list_b, free_strings);
        clinkedlist_destroy(link_flags_list_b);
    }
    
    if (ignore_list){
        if (ignore_list->length) clinkedlist_for_each(ignore_list, free_strings);
        clinkedlist_destroy(ignore_list);
    }
    
    if (out_files){
        if (out_files->length) clinkedlist_for_each(out_files, free_strings);
        clinkedlist_destroy(out_files);
    }
    
    redbuild_debug("Finished cleanup");
    
    compile_list = clinkedlist_create();
    preproc_flags_list = clinkedlist_create();
    includes = clinkedlist_create();
    link_libs = clinkedlist_create();
    comp_flags_list = clinkedlist_create();
    link_flags_list_f = clinkedlist_create();
    link_flags_list_b = clinkedlist_create();
    ignore_list = clinkedlist_create();
    out_files = clinkedlist_create();
}

bool source(const char *name){
    redbuild_debug("Adding %s",name);
    if (!compile_list){ printf("Error: new_module not called"); return false; }
    push_lit(compile_list, name);
    return false;
}

void add_dependency(dependency_type type, char *include, char *link, char* build, bool use_make){
    if (!homedir) homedir = gethomedir();
    if (include && strlen(include)){
        string s = string_replace_character(include, '~', (char*)homedir);
        string sf = string_format("-I%s ",s.data);
        push_lit(includes, sf.data);
        string_free(s);
        string_free(sf);
    } 
    if (link && strlen(link)){
        string l = {};
        string s = string_replace_character(link, '~', (char*)homedir);
        switch (type) {
            case dep_local: l = string_format(" %s", s.data); break;
            case dep_system: l = string_format(" -l%s",s.data); break;
            case dep_framework: l = string_format(" -framework %s",s.data); break;
        }
        if (l.data){
            push_lit(link_libs, l.data);
            string_free(l);
        }
        string_free(s);
    } 
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
    push_lit(preproc_flags_list, name);
}

void add_compilation_flag(char *name){
    push_lit(comp_flags_list, name);
}

void add_linker_flag(char *name, bool back){
    push_lit(back ? link_flags_list_b : link_flags_list_f, name);
}

void list_strings(void *data){
    string *s = (string*)data;
    buffer_write(&buf, s->data);
    buffer_write_space(&buf);
}

void process_preproc_flags(void *data){
    string *s = (string*)data;
    buffer_write(&buf, "-D%s",s->data);
    buffer_write_space(&buf);
}

void process_comp_flags(void *data){
    string *s = (string*)data;
    buffer_write(&buf, "-W%s",s->data);
    buffer_write_space(&buf);
}

void prepare_command(){
    redbuild_debug("Setting up output...");
    prepare_output();
    redbuild_debug("Target set. Common setup...");
    common();
    redbuild_debug("Common setup done. Platform-specific setup...");
    
    if (compilation_target == target_redacted) red_mod();
    else cross_mod();
    
    redbuild_debug("Platform-specific setup done.");
    redbuild_debug("Beginning compilation process");
    if (buf.buffer) buffer_destroy(&buf);
    buf = buffer_create(1024, buffer_can_grow);
    buffer_write(&buf, chosen_compiler);
    buffer_write_space(&buf);
    
    clinkedlist_for_each(preproc_flags_list, process_preproc_flags);
    clinkedlist_for_each(link_flags_list_f, list_strings);
    clinkedlist_for_each(includes, list_strings);
    clinkedlist_for_each(compile_list, list_strings);
    clinkedlist_for_each(link_libs, list_strings);
    clinkedlist_for_each(comp_flags_list, process_comp_flags);
    clinkedlist_for_each(link_flags_list_b, list_strings);
    
    buffer_write(&buf, "-o %s",output);
    redbuild_debug("Final compilation command:");
    printl(buf.buffer);
}

//TODO: lib support
bool compile(){
    prepare_command();
    print("Compiling");
    return system(buf.buffer) == 0;
}

void emit_argument(string_slice slice){
    if (!slice.length) return;
    buffer_write(&ccbuf,"\"%v\"",slice);
    buffer_write(&ccbuf,",\n");
}

bool gen_compile_commands(){
    // prepare_command();
    ccbuf = buffer_create(buf.buffer_size + 1024, buffer_can_grow);
    //TODO: use code formatter
    buffer_write(&ccbuf,"[\{\n\"arguments\": [\n");
    string_split(buf.buffer,' ',emit_argument);
    ccbuf.buffer_size -= 2;//TODO: one of my stupidest hacks right here
    ccbuf.cursor -= 2;
    buffer_write(&ccbuf,"\n],\n\"directory\": \"");
    buffer_write(&ccbuf,get_current_dir());
    buffer_write(&ccbuf,"\",\n\"file\": \"");
    buffer_write(&ccbuf,get_current_dir());
    buffer_write(&ccbuf,"/main.c\",\n\"output\": \"");
    buffer_write(&ccbuf,get_current_dir());
    buffer_write(&ccbuf,"/%s\"}]",output);
    write_full_file("compile_commands.json",ccbuf.buffer,ccbuf.buffer_size);
}

int run(){
    string s = string_format("./%s",output);
    int result = system(s.data);
    string_free(s);
    return result;
}

bool cred_compile(){
    buffer b = buffer_create(1024, buffer_can_grow);
    buffer_write_const(&b, "cred ");
    clinkedlist_for_each(compile_list, list_strings);
    buffer_write(&b, "-o %s",output_name);
    redbuild_debug("Final compilation command:");
    printl(b.buffer);
    redbuild_debug("Generating C code");
    int ret = system(b.buffer) == 0;
    buffer_destroy(&b);
    return ret;
}

bool quick_cred(const char *input_file, const char *output_file){
    buffer b = buffer_create(1024, buffer_can_grow);
    buffer_write(&b, "cred %s -o %s",input_file,output_file);
    redbuild_debug("Final compilation command:");
    printl(b.buffer);
    redbuild_debug("Generating C code");
    int ret = system(b.buffer) == 0;
    buffer_destroy(&b);
    return ret;
}

int comp_str(void *a, void *b){
    return strcmp(((string*)a)->data,(char*)b);
}

void handle_files(const char *directory, const char *name){
    if (strend(name, extension)) return;
    if (clinkedlist_find(ignore_list, (char*)name, comp_str)) {
        redbuild_debug("Ignoring %s",name);
        return;
    }
    string n = string_format("%s/%s",directory,name);
    push_lit(compile_list, n.data);
    
    string o = string_format("%s/%v.o ", directory, make_string_slice(name,0,strlen(name)-2));
    push_lit(out_files, o.data);
}

void find_files(char *ext){
    
    redbuild_debug("Adding all non-ignored files with %s extension",ext);
    
    char *cwd = get_current_dir();
    if (!cwd) { printf("No path"); return; }
    
    traverse_directory(cwd, true, handle_files);
}

bool ignore_source(const char *name){
    redbuild_debug("Will ignore %s",name);
    push_lit(ignore_list, name);
    return false;
}

bool source_all(const char *ext){
    extension = (char*)ext;
    find_files((char*)ext);
    return false;
}

void install(const char *location){
    string s = string_format("cp -r %s.red %s", output_name, location);
    system(s.data);
    string_free(s);
}

void rebuild_self(){
    
}

bool make_run(const char *directory, const char *command){
    buffer b = buffer_create(256, buffer_can_grow);
    buffer_write(&b, "make -C %s %s",directory, command);
    redbuild_debug("Final make command %s",b.buffer);
    return system(b.buffer) == 0;
}