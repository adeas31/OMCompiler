// This file defines templates for transforming Modelica/MetaModelica code to C
// code. They are used in the code generator phase of the compiler to write
// target code.
//
// CodegenC.tpl has the root template translateModel while
// this template contains only translateFunctions.
// These templates do not return any
// result but instead write the result to files. All other templates return
// text and are used by the root templates (most of them indirectly).

package CodegenCFunctions

import interface SimCodeTV;
import CodegenUtil.*;

/* public */ template generateEntryPoint(Path entryPoint, String url) "used in Compiler/Script/CevalScript.mo"
::=
let name = ("omc_" + underscorePath(entryPoint))
<<
/* This is an automatically generated entry point to a MetaModelica function */

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(OMC_ENTRYPOINT_STATIC)

#include <stdio.h>
#include <openmodelica.h>

DLLImport extern int __omc_main(int argc, char **argv);

int main(int argc, char **argv)
{
  return __omc_main(argc, argv);
}

#else

#include <meta/meta_modelica.h>
#include <stdio.h>
extern void <%name%>(threadData_t*,modelica_metatype);

void (*omc_assert)(threadData_t*,FILE_INFO info,const char *msg,...) __attribute__((noreturn)) = omc_assert_function;
void (*omc_assert_warning)(FILE_INFO info,const char *msg,...) = omc_assert_warning_function;
void (*omc_terminate)(FILE_INFO info,const char *msg,...) = omc_terminate_function;
void (*omc_throw)(threadData_t*) __attribute__ ((noreturn)) = omc_throw_function;

#ifdef _OPENMP
#include<omp.h>
/* Hack to make gcc-4.8 link in the OpenMP runtime if -fopenmp is given */
int (*force_link_omp)(void) = omp_get_num_threads;
#endif

static int rml_execution_failed()
{
  fflush(NULL);
  fprintf(stderr, "Execution failed!\n");
  fflush(NULL);
  return 1;
}

DLLExport int __omc_main(int argc, char **argv)
{
  MMC_INIT();
  {
  void *lst = mmc_mk_nil();
  int i = 0;

  for (i=argc-1; i>0; i--) {
    lst = mmc_mk_cons(mmc_mk_scon(argv[i]), lst);
  }

  <%mainTop('<%name%>(threadData, lst);',url)%>
  }

  <%if Flags.isSet(HPCOM) then "terminateHpcOmThreads();" %>
  fflush(NULL);
  EXIT(0);
  return 0;
}

#endif

#if defined(__cplusplus)
} /* end extern "C" */
#endif

>>
end generateEntryPoint;

template mainTop(Text mainBody, String url)
::=
  <<
  {
    MMC_TRY_TOP()

    MMC_TRY_STACK()

    <%mainBody%>

    MMC_ELSE()
    rml_execution_failed();
    fprintf(stderr, "Stack overflow detected and was not caught.\nSend us a bug report at <%url%>\n    Include the following trace:\n");
    printStacktraceMessages();
    fflush(NULL);
    return 1;
    MMC_CATCH_STACK()

    MMC_CATCH_TOP(return rml_execution_failed());
  }
  >>
end mainTop;

/* public */ template translateFunctions(FunctionCode functionCode)
  "Generates C code and Makefile for compiling and calling Modelica and
  MetaModelica functions.
  used in Compiler/SimCode/SimCodeMain.mo"
::=
  match functionCode
  case fc as FUNCTIONCODE(__) then
    let()= System.tmpTickResetIndex(0,2) /* auxFunction index */
    let &staticPrototypes = buffer ""
    let filePrefix = name
    let _= (if mainFunction then textFile(functionsMakefile(functionCode), '<%filePrefix%>.makefile'))
    let()= textFile(functionsHeaderFile(filePrefix, mainFunction, functions, extraRecordDecls, staticPrototypes), '<%filePrefix%>.h')
    let()= textFileConvertLines(functionsFile(filePrefix, mainFunction, functions, literals, staticPrototypes), '<%filePrefix%>.c')
    let()= textFile(externalFunctionIncludes(fc.externalFunctionIncludes), '<%filePrefix%>_includes.h')
    let()= textFile(recordsFile(filePrefix, extraRecordDecls), '<%filePrefix%>_records.c')
    // If ParModelica generate the kernels file too.
    if acceptParModelicaGrammar() then
      let()= textFile(functionsParModelicaKernelsFile(filePrefix, mainFunction, functions), '<%filePrefix%>_kernels.cl')
    "" // Return empty result since result written to files directly
  end match
end translateFunctions;

template functionsFile(String filePrefix,
                       Option<Function> mainFunction,
                       list<Function> functions,
                       list<Exp> literals,
                       Text &staticPrototypes)
 "Generates the contents of the main C file for the function case."
::=
  let &preLit = buffer ""
  let literalsRes = literals |> literal hasindex i0 fromindex 0 => literalExpConst(literal,i0,&preLit) ; separator="\n";empty
  <<
  #include "<%filePrefix%>.h"
  <% preLit %>
  <% /* Note: The literals may not be part of the header due to separate compilation */
     literalsRes
  %>
  #include "util/modelica.h"

  #include "<%filePrefix%>_includes.h"

  <%if staticPrototypes then
  <<
  /* default, do not make protected functions static */
  #if !defined(PROTECTED_FUNCTION_STATIC)
  #define PROTECTED_FUNCTION_STATIC
  #endif
  <%staticPrototypes%>
  >>
  %>

  <% if mainFunction then
  <<
  void (*omc_assert)(threadData_t*,FILE_INFO info,const char *msg,...) __attribute__((noreturn)) = omc_assert_function;
  void (*omc_assert_warning)(FILE_INFO info,const char *msg,...) = omc_assert_warning_function;
  void (*omc_terminate)(FILE_INFO info,const char *msg,...) = omc_terminate_function;
  void (*omc_throw)(threadData_t*) __attribute__ ((noreturn)) = omc_throw_function;
  >> %>

  <%match mainFunction case SOME(fn) then functionBody(fn,true,false)%>
  <%functionBodies(functions,false)%>
  <%\n%>
  >>
end functionsFile;

template functionsHeaderFile(String filePrefix,
                       Option<Function> mainFunction,
                       list<Function> functions,
                       list<RecordDeclaration> extraRecordDecls,
                       Text &staticPrototypes)
 "Generates the contents of the main C file for the function case."
::=
  <<
  #ifndef <%stringReplace(filePrefix,".","_")%>__H
  #define <%stringReplace(filePrefix,".","_")%>__H
  <%commonHeader(filePrefix)%>
  #ifdef __cplusplus
  extern "C" {
  #endif

  <%extraRecordDecls |> rd => recordDeclarationHeader(rd) ;separator="\n"%>

  <%match mainFunction case SOME(fn) then functionHeader(fn,true,false,staticPrototypes)%>

  <%functionHeaders(functions, false, staticPrototypes)%>

  #ifdef __cplusplus
  }
  #endif
  #endif<%\n%>
  >>
  /* adrpo: leave a newline at the end of file to get rid of the warning */
end functionsHeaderFile;

template functionsMakefile(FunctionCode fnCode)
 "Generates the contents of the makefile for the function case."
::=
match fnCode
case FUNCTIONCODE(makefileParams=MAKEFILE_PARAMS(__)) then
  let libsStr = (makefileParams.libs ;separator=" ")
  let ParModelicaExpLibs = if acceptParModelicaGrammar() then '-lOMOCLRuntime -lOpenCL' // else ""

  <<
  # Makefile generated by OpenModelica

  # Dynamic loading uses -O0 by default
  SIM_OR_DYNLOAD_OPT_LEVEL=-O0
  CC=<%if acceptParModelicaGrammar() then 'g++' else '<%makefileParams.ccompiler%>'%>
  CXX=<%makefileParams.cxxcompiler%>
  LINK=<%makefileParams.linker%>
  EXEEXT=<%makefileParams.exeext%>
  DLLEXT=<%makefileParams.dllext%>
  DEBUG_FLAGS=<% if boolOr(acceptMetaModelicaGrammar(), Flags.isSet(Flags.GEN_DEBUG_SYMBOLS)) then " -g"%>
  CFLAGS= -I"<%makefileParams.omhome%>/include/omc/c" <%makefileParams.includes ; separator=" "%> $(DEBUG_FLAGS) <%makefileParams.cflags%>
  LDFLAGS= -L"<%makefileParams.omhome%>/lib/<%getTriple()%>/omc" -Wl,-rpath,'<%makefileParams.omhome%>/lib/<%getTriple()%>/omc' <%ParModelicaExpLibs%> <%makefileParams.ldflags%> <%makefileParams.runtimelibs%>
  PERL=perl
  MAINFILE=<%name%>.c

  .PHONY: <%name%>
  <%name%>: $(MAINFILE) <%name%>.h <%name%>_records.c
  <%\t%> $(CC) $(CFLAGS) -c -o <%name%>.o $(MAINFILE)
  <%\t%> $(CC) $(CFLAGS) -c -o <%name%>_records.o <%name%>_records.c
  <%\t%> $(LINK) -o <%name%>$(DLLEXT) <%name%>.o <%name%>_records.o <%libsStr%> $(CFLAGS) $(LDFLAGS) -lm
  >>
end functionsMakefile;

template commonHeader(String filePrefix)
::=
  <<
  #include "meta/meta_modelica.h"
  #include "util/modelica.h"
  #include <stdio.h>
  #include <stdlib.h>
  #include <errno.h>
  <%if acceptParModelicaGrammar() then
  <<
  #include <ParModelica/explicit/openclrt/omc_ocl_interface.h>
  /* the OpenCL Kernels file name needed in libOMOCLRuntime.a */
  const char* omc_ocl_kernels_source = "<%filePrefix%>_kernels.cl";
  /* the OpenCL program. Made global to avoid repeated builds */
  extern cl_program omc_ocl_program;
  /* The default OpenCL device. If not set (=0) show the selection option.*/
  unsigned int default_ocl_device = <%getDefaultOpenCLDevice()%>;
  >>
  %>

  >>
end commonHeader;


/* public */ template externalFunctionIncludes(list<String> includes)
 "Generates external includes part in function files.
  used in Compiler/Template/CodegenFMU.tpl"
::=
  if includes then
  <<
  #ifdef __cplusplus
  extern "C" {
  #endif
  <% (includes ;separator="\n") %>
  #ifdef __cplusplus
  }
  #endif<%\n%>
  >>
end externalFunctionIncludes;

template functionHeaders(list<Function> functions, Boolean isSimulation, Text &staticPrototypes)
 "Generates function header part in function files."
::=
  (functions |> fn => functionHeader(fn, false, isSimulation, staticPrototypes) ; separator="\n\n")
end functionHeaders;

template functionHeadersParModelica(String filePrefix, list<Function> functions)
 "Generates the content of the C file for functions in the simulation case."
::=
  <<
  #ifndef <%stringReplace(filePrefix,".","_")%>__H
  #define <%stringReplace(filePrefix,".","_")%>__H
  //#include "helper.cl"

  <%parallelFunctionHeadersImpl(functions)%>

  #endif

  <%\n%>
  >>
  /* adrpo: leave a newline at the end of file to get rid of the warning */
end functionHeadersParModelica;

template parallelFunctionHeadersImpl(list<Function> functions)
 "Generates function header part in function files."
::=
  (functions |> fn => parallelFunctionHeader(fn, false) ; separator="\n\n")
end parallelFunctionHeadersImpl;

template functionHeader(Function fn, Boolean inFunc, Boolean isSimulation, Text &staticPrototypes)
 "Generates function header part in function files."
::=
  match fn
    case FUNCTION(__) then
      <<
      <%functionHeaderNormal(underscorePath(name), functionArguments, outVars, inFunc, visibility, false, isSimulation, staticPrototypes)%>
      <%functionHeaderBoxed(underscorePath(name), functionArguments, outVars, inFunc, isBoxedFunction(fn), visibility, false, isSimulation, staticPrototypes)%>
      >>
    case KERNEL_FUNCTION(__) then
      <<
      <%functionHeaderKernelFunctionInterface(underscorePath(name), functionArguments, outVars)%>
      >>
    case EXTERNAL_FUNCTION(dynamicLoad=true) then
      <<
      <%functionHeaderNormal(underscorePath(name), funArgs, outVars, inFunc, visibility, true, isSimulation, staticPrototypes)%>
      <%functionHeaderBoxed(underscorePath(name), funArgs, outVars, inFunc, isBoxedFunction(fn), visibility, true, isSimulation, staticPrototypes)%>

      <%extFunDefDynamic(fn)%>
      >>
    case EXTERNAL_FUNCTION(__) then
      <<
      <%functionHeaderNormal(underscorePath(name), funArgs, outVars, inFunc, visibility, false, isSimulation, staticPrototypes)%>
      <%functionHeaderBoxed(underscorePath(name), funArgs, outVars, inFunc, isBoxedFunction(fn), visibility, false, isSimulation, staticPrototypes)%>

      <%extFunDef(fn)%>
      >>
    case RECORD_CONSTRUCTOR(__) then
      let fname = underscorePath(name)
      let funArgsStr = (funArgs |> var as VARIABLE(__) => ', <%varType(var)%> <%crefStr(name)%>')
      <<
      <% match visibility case PUBLIC() then "DLLExport" %>
      <%fname%> omc_<%fname%>(threadData_t *threadData<%funArgsStr%>); /* record head */

      <%functionHeaderBoxed(fname, funArgs, boxedRecordOutVars, inFunc, false, visibility, false, isSimulation, staticPrototypes)%>
      >>
end functionHeader;

template parallelFunctionHeader(Function fn, Boolean inFunc)
 "Generates function header part in function files."
::=
  match fn
    case PARALLEL_FUNCTION(__) then
      <<
      <%functionHeaderParallelImpl(underscorePath(name), functionArguments, outVars, inFunc, false)%>
      >>
end parallelFunctionHeader;

template functionHeaderParallelImpl(String fname, list<Variable> fargs, list<Variable> outVars, Boolean inFunc, Boolean boxed)
 "Generates parmodelica paralell function header part in kernels files."
::=
    let fargsStr =  (fargs |> var => funArgDefinition(var) ;separator=", ")
    if outVars then
  <<
    <%outVars |> _ hasindex i1 fromindex 1 => '#define <%fname%>_rettype_<%i1%> c<%i1%>' ;separator="\n"%>
    typedef struct <%fname%>_rettype_s
    {
      <%outVars |> var hasindex i1 fromindex 1 =>
        match var
        case VARIABLE(__) then
          let dimStr = match ty case T_ARRAY(__)
                       then '[<%dims |> dim => dimension(dim) ;separator=", "%>]'
          let typeStr = if boxed then varTypeBoxed(var) else varType(var)
          '<%typeStr%> c<%i1%>; /* <%crefStr(name)%><%dimStr%> */'
        case FUNCTION_PTR(__) then
          'modelica_fnptr c<%i1%>; /* <%name%> */'
      ;separator="\n";empty
      %>
    } <%fname%>_rettype;

  <%fname%>_rettype omc_<%fname%>(<%fargsStr%>);

    >>
end functionHeaderParallelImpl;

template recordDeclaration(RecordDeclaration recDecl)
 "Generates structs for a record declaration."
::=
  match recDecl
  case RECORD_DECL_FULL(__) then
    <<
    <%recordDefinition(dotPath(defPath),
                      underscorePath(defPath),
                      (variables |> VARIABLE(__) => '"_<%crefStr(name)%>"' ;separator=","),
                      listLength(variables))%>
    >>
  case RECORD_DECL_DEF(__) then
    <<
    <%recordDefinition(dotPath(path),
                      underscorePath(path),
                      (fieldNames |> name => '"<%name%>"' ;separator=","),
                      listLength(fieldNames))%>
    >>
end recordDeclaration;

template recordDeclarationHeader(RecordDeclaration recDecl)
 "Generates structs for a record declaration."
::=
  match recDecl
  case r as RECORD_DECL_FULL(__) then
    <<
    <% match aliasName
    case SOME(str) then 'typedef <%str%> <%r.name%>;'
    else <<
    typedef struct <%r.name%>_s {
      <%r.variables |> var as VARIABLE(__) => '<%varType(var)%> _<%crefStr(var.name)%>;' ;separator="\n"%>
    } <%r.name%>;
    >> %>
    typedef base_array_t <%name%>_array;
    <%recordDefinitionHeader(dotPath(defPath),
                      underscorePath(defPath),
                      listLength(variables))%>
    >>
  case RECORD_DECL_DEF(__) then
    <<
    <%recordDefinitionHeader(dotPath(path),
                      underscorePath(path),
                      listLength(fieldNames))%>
    >>
end recordDeclarationHeader;

template recordDefinition(String origName, String encName, String fieldNames, Integer numFields)
 "Generates the definition struct for a record declaration."
::=
  match encName
  case "SourceInfo_SOURCEINFO" then ''
  else
  /* adrpo: 2011-03-14 make MSVC happy, no arrays of 0 size! */
  let fieldsDescription =
      match numFields
       case 0 then
         'const char* <%encName%>__desc__fields[1] = {"no fields"};'
       case _ then
         'const char* <%encName%>__desc__fields[<%numFields%>] = {<%fieldNames%>};'
  <<
  #define <%encName%>__desc_added 1
  <%fieldsDescription%>
  struct record_description <%encName%>__desc = {
    "<%encName%>", /* package_record__X */
    "<%origName%>", /* package.record_X */
    <%encName%>__desc__fields
  };
  >>
end recordDefinition;

template recordDefinitionHeader(String origName, String encName, Integer numFields)
 "Generates the definition struct for a record declaration."
::=
  <<
  extern struct record_description <%encName%>__desc;
  >>
end recordDefinitionHeader;

template functionHeaderNormal(String fname, list<Variable> fargs, list<Variable> outVars, Boolean inFunc, SCode.Visibility visibility, Boolean dynLoad, Boolean isSimulation, Text &staticPrototypes)
::=functionHeaderImpl(fname, fargs, outVars, inFunc, false, visibility, dynLoad, isSimulation, staticPrototypes)
end functionHeaderNormal;

template functionHeaderBoxed(String fname, list<Variable> fargs, list<Variable> outVars, Boolean inFunc, Boolean isBoxed, SCode.Visibility visibility, Boolean dynLoad, Boolean isSimulation, Text &staticPrototypes)
::=
  let boxvar =
    <<
    static const MMC_DEFSTRUCTLIT(boxvar_lit_<%fname%>,2,0) {(void*) boxptr_<%fname%>,0}};
    #define boxvar_<%fname%> MMC_REFSTRUCTLIT(boxvar_lit_<%fname%>)<%\n%>
    >>
  <<
  <%if isBoxed then '#define boxptr_<%fname%> omc_<%fname%><%\n%>' else functionHeaderImpl(fname, fargs, outVars, inFunc, true, visibility, dynLoad, isSimulation, staticPrototypes)%>
  <% match visibility
    case PROTECTED(__) then
      let &staticPrototypes += (if isSimulation then "" else boxvar)
      if isSimulation then '<%boxvar%> /* boxvar early */' else ""
    else boxvar %>
  >>
end functionHeaderBoxed;

template functionHeaderImpl(String fname, list<Variable> fargs, list<Variable> outVars, Boolean inFunc, Boolean boxed, SCode.Visibility visibility, Boolean dynamicLoad, Boolean isSimulation, Text &staticPrototypes)
 "Generates function header for a Modelica/MetaModelica function. Generates a

  boxed version of the header if boxed = true, otherwise a normal header"
::=
  let prototype = functionPrototype(fname, fargs, outVars, boxed, visibility, isSimulation)
  let inFnStr = if boolAnd(boxed,inFunc) then
    <<
    DLLExport
    int in_<%fname%>(threadData_t *threadData, type_description * inArgs, type_description * outVar);
    >>
  match visibility
    case PROTECTED(__) then
      if isSimulation then
        if dynamicLoad then "" else '<%prototype%>;<%\n%>'
      else
        let &staticPrototypes += if dynamicLoad then "" else '<%prototype%>;<%\n%>'
        inFnStr
    else
      <<
      <%inFnStr%>
      <%if dynamicLoad then '' else 'DLLExport<%\n%><%prototype%>;'%>
      >>
end functionHeaderImpl;

template functionPrototype(String fname, list<Variable> fargs, list<Variable> outVars, Boolean boxed, SCode.Visibility visibility, Boolean isSimulation)
 "Generates function header definition for a Modelica/MetaModelica function. Generates a boxed version of the header if boxed = true, otherwise a normal definition"
::=
  let static = if isSimulation then "" else (match visibility case PROTECTED(__) then 'PROTECTED_FUNCTION_STATIC ')
  let fargsStr = if boxed then
      (fargs |> var => ", " + funArgBoxedDefinition(var) )
    else
      (fargs |> var => ", " + funArgDefinition(var) )
  let outarg = (match outVars
    case {} then "void"
    case var::_ then (match var
    case VARIABLE(__) then if boxed then varTypeBoxed(var) else varType(var)
    case FUNCTION_PTR(__) then "modelica_fnptr"))
  let boxPtrStr = if boxed then "boxptr" else "omc"
  if outVars then
    let outargs = List.rest(outVars) |> var => ", " + (match var
      case var as VARIABLE(__) then '<%if boxed then varTypeBoxed(var) else varType(var)%> *out<%funArgName(var)%>'
      case FUNCTION_PTR(__) then 'modelica_fnptr *out<%funArgName(var)%>')
    '<%static%><%outarg%> <%boxPtrStr%>_<%fname%>(threadData_t *threadData<%fargsStr%><%outargs%>)'
  else
  '<%static%>void <%boxPtrStr%>_<%fname%>(threadData_t *threadData<%fargsStr%>)'
end functionPrototype;

template functionHeaderKernelFunctionInterface(String fname, list<Variable> fargs, list<Variable> outVars)
 "Generates function header for a ParModelica Kernel function interface."
::=
  '<%functionHeaderKernelFunctionInterfacePrototype(fname, fargs, outVars)%>;'
end functionHeaderKernelFunctionInterface;

template functionHeaderKernelFunctionInterfacePrototype(String fname, list<Variable> fargs, list<Variable> outVars)
 "Generates function header for a ParModelica Kernel function interface."
::=
  let fargsStr = 'threadData_t *threadData'
  let &fargsStr += if fargs then ", " + (fargs |> var => funArgDefinitionKernelFunctionInterface(var) ;separator=", ")
  // let &fargsStr += if outVars then ", " + (outVars |> var => tupleOutfunArgDefinitionKernelFunctionInterface(var) ;separator=", ")
  // 'void omc_<%fname%>(<%fargsStr%>)'

  match outVars
    case {} then
      'void omc_<%fname%>(<%fargsStr%>)'

    case fvar::rest then
      let rettype = functionArgTypeKernelInterface(fvar)
      let &fargsStr += if rest then ", " + (rest |> var => tupleOutfunArgDefinitionKernelFunctionInterface(var) ;separator=", ")
      '<%rettype%> omc_<%fname%>(<%fargsStr%>)'

    else
      error(sourceInfo(), 'functionHeaderKernelFunctionInterfacePrototype failed')
end functionHeaderKernelFunctionInterfacePrototype;

template funArgName(Variable var)
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(__) then contextCref(name,contextFunction,&auxFunction)
  case FUNCTION_PTR(__) then '_' + name
end funArgName;

template funArgDefinition(Variable var)
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(__) then ('<%varType(var)%> <%contextCref(name,contextFunction,&auxFunction)%>' + (if var.instDims then " = {0}"))
  case FUNCTION_PTR(__) then 'modelica_fnptr _<%name%>'
end funArgDefinition;

template funArgDefinitionKernelFunctionInterface(Variable var)
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(__) then
    '<%functionArgTypeKernelInterface(var)%> <%funArgName(var)%>'
  else error(sourceInfo(), 'funArgDefinitionKernelFunctionInterface : unsupported function argument type')
end funArgDefinitionKernelFunctionInterface;

template tupleOutfunArgDefinitionKernelFunctionInterface(Variable var)
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(__) then
    '<%functionArgTypeKernelInterface(var)%> *out<%funArgName(var)%>'
  else error(sourceInfo(), 'tupleOutfunArgDefinitionKernelFunctionInterface : unsupported function argument type')
end tupleOutfunArgDefinitionKernelFunctionInterface;

template functionArgTypeKernelInterface(Variable var)
::=
  match var
    case VARIABLE(ty=T_ARRAY(__), parallelism = PARGLOBAL(__)) then 'device_<%varType(var)%>'
    case VARIABLE(ty=T_ARRAY(__), parallelism = PARLOCAL(__)) then 'device_local_<%varType(var)%>'
    case VARIABLE(__) then '<%varType(var)%>'
    else 'Invalid function argument to Kernel function Interface.'
end functionArgTypeKernelInterface;

template funArgDefinitionKernelFunctionBody(Variable var)
 "Generates code to initialize variables.
  Does not return anything: just appends declarations to buffers."
::=
let &auxFunction = buffer ""
match var
//function args will have nill instdims even if they are arrays. handled here
case var as VARIABLE(ty=T_ARRAY(__), parallelism = PARGLOBAL(__)) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  '__global modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,<%\n%>    __global modelica_integer* info_<%varName%>'

case var as VARIABLE(ty=T_ARRAY(__), parallelism = PARLOCAL(__)) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  '__local modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,<%\n%>    __local modelica_integer* info_<%varName%>'

case var as VARIABLE(__) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  if instDims then
    (match parallelism
    case PARGLOBAL(__) then
      '__global modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,<%\n%>    __global modelica_integer* info_<%varName%>'
    case PARLOCAL(__) then
      '__global modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,<%\n%>    __global modelica_integer* info_<%varName%>'
    )
  else
    'modelica_<%expTypeShort(var.ty)%> <%varName%>'

else '#error Unknown variable type in as function argument funArgDefinitionKernelFunctionBody<%\n%>'
end funArgDefinitionKernelFunctionBody;

template funArgDefinitionKernelFunctionBody2(Variable var, Text &parArgList /*BUFPA*/)
 "Generates code to initialize variables.
  Does not return anything: just appends declarations to buffers."
::=
let &auxFunction = buffer ""
match var
//function args will have nill instdims even if they are arrays. handled here
case var as VARIABLE(ty=T_ARRAY(__)) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  let &parArgList += ',<%\n%>    __global modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,'
  let &parArgList += '<%\n%>    __global modelica_integer* info_<%varName%>'
  ""
case var as VARIABLE(__) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  if instDims then
    let &parArgList += ',<%\n%>    __global modelica_<%expTypeShort(var.ty)%>* data_<%varName%>,'
    let &parArgList += '<%\n%>    __global modelica_integer* info_<%varName%>'
  " "
  else
    let &parArgList += ',<%\n%>    modelica_<%expTypeShort(var.ty)%> <%varName%>'
  ""
else let &parArgList += '    #error Unknown variable type in as function argument funArgDefinitionKernelFunctionBody2<%\n%>' ""
end funArgDefinitionKernelFunctionBody2;

template parFunArgDefinitionFromLooptupleVar(tuple<DAE.ComponentRef,builtin.SourceInfo> tupleVar)
::=
match tupleVar
case tupleVar as ((cref as CREF_IDENT(identType = T_ARRAY(__)),_)) then
  let varName = contextArrayCref(cref,contextParallelFunction)
  match cref.identType
  case identType as T_ARRAY(ty = T_INTEGER(__)) then
    '__global modelica_integer* data_<%varName%>,<%\n%>__global modelica_integer* info_<%varName%>'
  case identType as T_ARRAY(ty = T_REAL(__)) then
    '__global modelica_real* data_<%varName%>,<%\n%>__global modelica_integer* info_<%varName%>'

  else 'Template error in parFunArgDefinitionFromLooptupleVar'

case tupleVar as ((cref as CREF_IDENT(__),_)) then
  let varName = contextArrayCref(cref,contextParallelFunction)
  match cref.identType
  case identType as T_INTEGER(__) then
    'modelica_integer <%varName%>'
  case identType as T_REAL(__) then
    'modelica_real <%varName%>'

  else 'Tempalte error in parFunArgDefinitionFromLooptupleVar'

end parFunArgDefinitionFromLooptupleVar;

template reconstructKernelArraysFromLooptupleVars(tuple<DAE.ComponentRef,builtin.SourceInfo> tupleVar, Text &reconstructedArrs)
 "reconstructs modelica arrays in the kernels."
::=
match tupleVar
case tupleVar as ((cref as CREF_IDENT(identType = T_ARRAY(__)),_)) then
  let varName = contextArrayCref(cref,contextParallelFunction)
  match cref.identType
  case identType as T_ARRAY(ty = T_INTEGER(__)) then
    let &reconstructedArrs += 'integer_array <%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.data = data_<%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.ndims = info_<%varName%>[0]; <%\n%>'
    let &reconstructedArrs += '<%varName%>.dim_size = info_<%varName%> + 1; <%\n%>'
    ""
  case identType as T_ARRAY(ty = T_REAL(__)) then
    let &reconstructedArrs += 'real_array <%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.data = data_<%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.ndims = info_<%varName%>[0]; <%\n%>'
    let &reconstructedArrs += '<%varName%>.dim_size = info_<%varName%> + 1; <%\n%>'
    ""
else let &reconstructedArrs += '#wiered variable in kerenl reconstruction of arrays<%\n%>' ""
end reconstructKernelArraysFromLooptupleVars;

template reconstructKernelArrays(Variable var, Text &reconstructedArrs)
 "reconstructs modelica arrays in the kernels."
::=
let &auxFunction = buffer ""
match var
//function args will have nill instdims even if they are arrays. handled here
case var as VARIABLE(ty=T_ARRAY(__),parallelism=PARGLOBAL(__)) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  let &reconstructedArrs += '<%expTypeShort(var.ty)%>_array <%varName%>; <%\n%>'
  let &reconstructedArrs += '<%varName%>.data = data_<%varName%>; <%\n%>'
  let &reconstructedArrs += '<%varName%>.ndims = info_<%varName%>[0]; <%\n%>'
  let &reconstructedArrs += '<%varName%>.dim_size = info_<%varName%> + 1; <%\n%>'
  ""
case var as VARIABLE(ty=T_ARRAY(__),parallelism=PARLOCAL(__)) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  let &reconstructedArrs += 'local_<%expTypeShort(var.ty)%>_array <%varName%>; <%\n%>'
  let &reconstructedArrs += '<%varName%>.data = data_<%varName%>; <%\n%>'
  let &reconstructedArrs += '<%varName%>.ndims = info_<%varName%>[0]; <%\n%>'
  let &reconstructedArrs += '<%varName%>.dim_size = info_<%varName%> + 1; <%\n%>'
  ""
case var as VARIABLE(__) then
  let varName = '<%contextCref(var.name,contextParallelFunction,&auxFunction)%>'
  if instDims then
    let &reconstructedArrs += '<%expTypeShort(var.ty)%>_array <%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.data = data_<%varName%>; <%\n%>'
    let &reconstructedArrs += '<%varName%>.ndims = info_<%varName%>[0]; <%\n%>'
    let &reconstructedArrs += '<%varName%>.dim_size = info_<%varName%> + 1; <%\n%>'
  " "
  else
  ""
else let &reconstructedArrs += '#wiered variable in kerenl reconstruction of arrays<%\n%>' ""
end reconstructKernelArrays;

template funArgBoxedDefinition(Variable var)
 "A definition for a boxed variable is always of type modelica_metatype,
  unless it's a function pointer"
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(__) then 'modelica_metatype <%contextCref(name,contextFunction,&auxFunction)%>'
  case FUNCTION_PTR(__) then 'modelica_fnptr _<%name%>'
end funArgBoxedDefinition;

template extFunDef(Function fn)
 "Generates function header for an external function."
::=
match fn
case func as EXTERNAL_FUNCTION(__) then
  let fn_name = extFunctionName(extName, language)
  let fargsStr = extFunDefArgs(extArgs, language)
  let fargsStrEscaped = '<%escapeCComments(fargsStr)%>'
  let includesStr = includes |> i => i ;separator=", "
  /*
   * adrpo:
   *   only declare the external function definition IF THERE WERE NO INCLUDES!
   *   i did not put includesStr string in the comment below as it might include
   *   entire files
   */
  if  includes then
    <<
    /*
     * The function has annotation(Include=...>)
     * the external function definition should be present
     * in one of these files and have this prototype:
     * extern <%extReturnType(extReturn)%> <%fn_name%>(<%fargsStrEscaped%>);
     */
    >>
  else
    <<
    extern <%extReturnType(extReturn)%> <%fn_name%>(<%fargsStr%>);
    >>
end match
end extFunDef;

template extFunDefDynamic(Function fn)
 "Generates function header for an external function."
::=
match fn
case func as EXTERNAL_FUNCTION(__) then
  let fn_name = extFunctionName(extName, language)
  let fargsStr = extFunDefArgs(extArgs, language)
  <<
  typedef <%extReturnType(extReturn)%> (*ptrT_<%fn_name%>)(<%fargsStr%>);
  extern ptrT_<%fn_name%> ptr_<%fn_name%>;
  >>
end extFunDefDynamic;

/* public */ template extFunctionName(String name, String language) "used in Compiler/Template/CodegenFMU.tpl"
::=
  match language
  case "C" then '<%name%>'
  case "FORTRAN 77" then '<%name%>_'
  else error(sourceInfo(), 'Unsupport external language: <%language%>')
end extFunctionName;

template extFunDefArgs(list<SimExtArg> args, String language)
::=
  match language
  case "C" then (args |> arg => extFunDefArg(arg) ;separator=", ")
  case "FORTRAN 77" then (args |> arg => extFunDefArgF77(arg) ;separator=", ")
  else error(sourceInfo(), 'Unsupport external language: <%language%>')
end extFunDefArgs;

template extReturnType(SimExtArg extArg)
 "Generates return type for external function."
::=
  match extArg
  case ex as SIMEXTARG(__)    then extType(type_,true /*Treat this as an input (pass by value)*/,false)
  case SIMNOEXTARG(__)  then "void"
  case SIMEXTARGEXP(__) then error(sourceInfo(), 'Expression types are unsupported as return arguments <%printExpStr(exp)%>')
  else error(sourceInfo(), "Unsupported return argument")
end extReturnType;


template extType(Type type, Boolean isInput, Boolean isArray)
 "Generates type for external function argument or return value."
::=
  let s = match type
  case T_INTEGER(__)     then "int"
  case T_REAL(__)        then "double"
  case T_STRING(__)      then "const char*"
  case T_BOOL(__)        then "int"
  case T_ENUMERATION(__) then "int"
  case T_ARRAY(__)       then extType(ty,isInput,true)
  case T_COMPLEX(complexClassType=EXTERNAL_OBJ(__))
                      then "void *"
  case T_COMPLEX(complexClassType=RECORD(path=rname))
                      then '<%underscorePath(rname)%>'
  case T_METATYPE(__)
  case T_METABOXED(__)
       then "modelica_metatype"
  case T_FUNCTION_REFERENCE_VAR(__)
       then "modelica_fnptr"
  else error(sourceInfo(), 'Unknown external C type <%unparseType(type)%>')
  match type case T_ARRAY(__) then s else if isInput then (if isArray then '<%match s case "const char*" then "" else "const "%><%s%>*' else s) else '<%s%>*'
end extType;

template extTypeF77(Type type, Boolean isReference)
  "Generates type for external function argument or return value for F77."
::=
  let s = match type
  case T_INTEGER(__)     then "int"
  case T_REAL(__)        then "double"
  case T_STRING(__)      then "char"
  case T_BOOL(__)        then "int"
  case T_ENUMERATION(__) then "int"
  case T_ARRAY(__)       then extTypeF77(ty, true)
  case T_COMPLEX(complexClassType=EXTERNAL_OBJ(__))
                         then "void*"
  case T_COMPLEX(complexClassType=RECORD(path=rname))
                         then '<%underscorePath(rname)%>'
  case T_METATYPE(__) case T_METABOXED(__) then "void*"
  else error(sourceInfo(), 'Unknown external F77 type <%unparseType(type)%>')
  match type case T_ARRAY(__) then s else if isReference then '<%s%>*' else s
end extTypeF77;

template extFunDefArg(SimExtArg extArg)
 "Generates the definition of an external function argument.
  Assume that language is C for now."
::=
  let &auxFunction = buffer ""
  match extArg
  case SIMEXTARG(cref=c, isInput=ii, isArray=ia, type_=t) then
    let name = contextCref(c,contextFunction,&auxFunction)
    let typeStr = extType(t,ii,ia)
    <<
    <%typeStr%> /*<%name%>*/
    >>
  case SIMEXTARGEXP(__) then
    let typeStr = extType(type_,true,false)
    <<
    <%typeStr%>
    >>
  case SIMEXTARGSIZE(cref=c) then
    <<
    size_t
    >>
end extFunDefArg;

template extFunDefArgF77(SimExtArg extArg)
::=
  let &auxFunction = buffer ""
  match extArg
  case SIMEXTARG(cref=c, isInput = isInput, type_=t) then
    let name = contextCref(c,contextFunction,&auxFunction)
    let typeStr = '<%extTypeF77(t,true)%>'
    '<%typeStr%> /*<%name%>*/'

  case SIMEXTARGEXP(__) then '<%extTypeF77(type_,true)%>'

  /* adpro: 2011-06-23
   * DO NOT USE CONST HERE as sometimes is used with size(A, 1)

   * sometimes with n in Modelica.Math.Matrices.Lapack and you
   * get conflicting external definitions in the same Model_function.h
   * file
   */
  case SIMEXTARGSIZE(__) then 'int *'
end extFunDefArgF77;


template functionName(Function fn, Boolean dotPath)
::=
  match fn
  case FUNCTION(__)
  case EXTERNAL_FUNCTION(__)
  case RECORD_CONSTRUCTOR(__) then if dotPath then dotPath(name) else underscorePath(name)
end functionName;


template functionBodies(list<Function> functions, Boolean isSimulation)
 "Generates the body for a set of functions."
::=
  (functions |> fn => functionBody(fn, false, isSimulation) ;separator="\n")
end functionBodies;

template functionBodiesParModelica(list<Function> functions)
 "Generates the body for a set of functions."
::=
  (functions |> fn => functionBodyParModelica(fn, false) ;separator="\n")
end functionBodiesParModelica;

template functionBody(Function fn, Boolean inFunc, Boolean isSimulation)
 "Generates the body for a function."
::=
  match fn
  case fn as FUNCTION(__)                    then functionBodyRegularFunction(fn, inFunc, isSimulation)
  case fn as KERNEL_FUNCTION(__)             then functionBodyKernelFunctionInterface(fn, inFunc)
  case fn as EXTERNAL_FUNCTION(__)           then functionBodyExternalFunction(fn, inFunc, isSimulation)
  case fn as RECORD_CONSTRUCTOR(__)          then functionBodyRecordConstructor(fn, isSimulation)
end functionBody;

template functionBodyParModelica(Function fn, Boolean inFunc)
 "Generates the body for a function."
::=
  match fn
  case fn as FUNCTION(__)                  then extractParforBodies(fn, inFunc)
  case fn as KERNEL_FUNCTION(__)           then functionBodyKernelFunction(fn, inFunc)
  case fn as PARALLEL_FUNCTION(__)         then functionBodyParallelFunction(fn, inFunc)
end functionBodyParModelica;

template extractParforBodies(Function fn, Boolean inFunc)
 "Generates the body for a Modelica/MetaModelica function."
::=
match fn
case FUNCTION(__) then
  let()= System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */

  let &varDecls = buffer ""
  let &auxFunction = buffer ""
  let bodyPart = (body |> stmt  => extractParFors(stmt, &varDecls, &auxFunction) ;separator="\n")
  <<
  <%auxFunction%>
  <%bodyPart%>
  >>
end extractParforBodies;

template functionBodyRegularFunction(Function fn, Boolean inFunc, Boolean isSimulation)
 "Generates the body for a Modelica/MetaModelica function."
::=
match fn
case FUNCTION(__) then
  let &auxFunction = buffer ""
  let()= codegenResetTryThrowIndex()
  let()= System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */
  let fname = underscorePath(name)
  let &varDecls = buffer ""
  let &varInits = buffer ""
  let &varFrees = buffer ""
  let &auxFunction = buffer ""
  let _ = (variableDeclarations |> var hasindex i1 fromindex 1 =>
      varInit(var, "", &varDecls, &varInits, &varFrees, &auxFunction) ; empty /* increase the counter! */
    )
  let bodyPart = (body |> stmt  => funStatement(stmt, &varDecls, &auxFunction) ;separator="\n")
  let outVarAssign = (List.restOrEmpty(outVars) |> var => varOutput(var))

  let freeConstructedExternalObjects = (variableDeclarations |> var as VARIABLE(ty=T_COMPLEX(complexClassType=EXTERNAL_OBJ(path=path_ext))) => 'omc_<%underscorePath(path_ext)%>_destructor(threadData,<%contextCref(var.name,contextFunction,&auxFunction)%>);'; separator = "\n")
  /* Needs to be done last as it messes with the tmp ticks :) */
  let &varDecls += addRootsTempArray()

  let boxedFn = functionBodyBoxed(fn, isSimulation)
  <<
  <%auxFunction%>
  <% match visibility case PUBLIC(__) then "DLLExport" %>
  <%functionPrototype(fname, functionArguments, outVars, false, visibility, isSimulation)%>
  {
    <%varDecls%>
    _tailrecursive: OMC_LABEL_UNUSED
    <%varInits%>
    <%bodyPart%>
    _return: OMC_LABEL_UNUSED
    <%outVarAssign%>
    <%if acceptParModelicaGrammar() then
    '/* Free GPU/OpenCL CPU memory */<%\n%><%varFrees%>'%>
    <%freeConstructedExternalObjects%>
    <%match outVars
       case {} then 'return;'
       case v::_ then 'return <%funArgName(v)%>;'
    %>
  }
  <% if inFunc then generateInFunc(fname,functionArguments,outVars) %>
  <%boxedFn%>
  >>
end functionBodyRegularFunction;

template generateInFunc(Text fname, list<Variable> functionArguments, list<Variable> outVars)
::=
  <<
  DLLExport
  int in_<%fname%>(threadData_t *threadData, type_description * inArgs, type_description * outVar)
  {
    //if (!mmc_GC_state) mmc_GC_init();
    <%functionArguments |> var => '<%funArgDefinition(var)%>;' ;separator="\n"%>
    <%outVars |> var => '<%funArgDefinition(var)%>;' ;separator="\n"%>
    <%functionArguments |> arg => readInVar(arg) ;separator="\n"%>
    MMC_TRY_TOP_INTERNAL()
    <%match outVars
        case v::_ then '<%funArgName(v)%> = '
      %>omc_<%fname%>(threadData<%functionArguments |> var => (", " + funArgName(var) )%><%List.restOrEmpty(outVars) |> var => (", &" + funArgName(var) )%>);
    MMC_CATCH_TOP(return 1)
    <% match outVars case {} then "write_noretcall(outVar);" case first::_ then writeOutVar(first) %>
    <% List.restOrEmpty(outVars) |> var => writeOutVar(var) ;separator="\n"; empty %>
    fflush(NULL);
    return 0;
  }
  #ifdef GENERATE_MAIN_EXECUTABLE
  static int rml_execution_failed()
  {
    fflush(NULL);
    fprintf(stderr, "Execution failed!\n");
    fflush(NULL);
    return 1;
  }

  int main(int argc, char **argv) {
    MMC_INIT();
    {
    void *lst = mmc_mk_nil();
    int i = 0;

    for (i=argc-1; i>0; i--) {
      lst = mmc_mk_cons(mmc_mk_scon(argv[i]), lst);
    }

    <%mainTop('omc_<%fname%>(threadData, lst);',"https://trac.openmodelica.org/OpenModelica/newticket")%>
    }

    <%if Flags.isSet(HPCOM) then "terminateHpcOmThreads();" %>
    fflush(NULL);
    EXIT(0);
    return 0;
  }
  #endif
  >>
end generateInFunc;

template functionBodyKernelFunction(Function fn, Boolean inFunc)
 "Generates the body for a ParModelica Kernel function."
::=
match fn
case KERNEL_FUNCTION(__) then
  let()= System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */
  let fname = underscorePath(name)

  //retTyep for kernels is always void
  //let retType = if outVars then '<%fname%>_rettype' else "void"

  let &varDecls = buffer ""
  let &varInits = buffer ""
  let &varFrees = buffer ""
  let &auxFunction = buffer ""
  let _ = (variableDeclarations |> var =>
      varInit(var, "", &varDecls, &varInits, &varFrees, &auxFunction) ; empty /* increase the counter! */
    )

  // This odd arrangment and call is to get the commas in the right places
  // between the argumetns.
  // This puts correct comma placment even when the 'outvar' list is empty
  let argStr = (functionArguments |> var => '<%funArgDefinitionKernelFunctionBody(var)%>' ;separator=", \n    ")
  //let &argStr += (outVars |> var => '<%parFunArgDefinition(var)%>' ;separator=", \n")
  let _ = (outVars |> var =>
     funArgDefinitionKernelFunctionBody2(var, &argStr) ;separator=",\n")

  // Reconstruct array arguments to structures in the kernels
  let &reconstrucedArrays = buffer ""
  let _ = (functionArguments |> var =>
      reconstructKernelArrays(var, &reconstrucedArrays)
    )
  let _ = (outVars |> var =>
      reconstructKernelArrays(var, &reconstrucedArrays)
    )

  let bodyPart = (body |> stmt  => parModelicafunStatement(stmt, &varDecls, &auxFunction) ;separator="\n")

  /* Needs to be done last as it messes with the tmp ticks :) */
  let &varDecls += addRootsTempArray()

  <<
  <%auxFunction%>

  __kernel void omc_<%fname%>(
    <%\t%><%\t%><%argStr%>)
  {
    /* functionBodyKernelFunction: Reconstruct Arrays */
    <%reconstrucedArrays%>

    /* functionBodyKernelFunction: locals */
    <%varDecls%>

    /* functionBodyKernelFunction: var inits */
    <%varInits%>
    /* functionBodyKernelFunction: body */
    <%bodyPart%>

    /* Free GPU/OpenCL CPU memory */
    <%varFrees%>
  }

  >>
end functionBodyKernelFunction;

//Generates the body of a parallel function
template functionBodyParallelFunction(Function fn, Boolean inFunc)
 "Generates the body for a Modelica parallel function."
::=
match fn
case PARALLEL_FUNCTION(__) then
  let()= System.tmpTickReset(1)
  let fname = underscorePath(name)
  let retType = if outVars then '<%fname%>_rettype' else "void"
  let &varDecls = buffer ""
  let &varInits = buffer ""
  let &varFrees = buffer ""
  let &auxFunction = buffer ""
  let retVar = if outVars then tempDecl(retType, &varDecls)
  let _ = (variableDeclarations |> var hasindex i1 fromindex 1 =>
      varInitParallel(var, "", i1, &varDecls, &varInits, &varFrees, &auxFunction)
      ;empty
    )
  let bodyPart = (body |> stmt  => parModelicafunStatement(stmt, &varDecls, &auxFunction) ;separator="\n")
  let &outVarInits = buffer ""
  let &outVarCopy = buffer ""
  let &outVarAssign = buffer ""
  let _1 = (outVars |> var hasindex i1 fromindex 1 =>
      varOutputParallel(var, retVar, i1, &varDecls, &outVarInits, &outVarCopy, &outVarAssign, &auxFunction)
      ;separator="\n"; empty
    )


  <<
  <%auxFunction%>
  <%retType%> omc_<%fname%>(<%functionArguments |> var => funArgDefinition(var) ;separator=", "%>)
  {
    <%varDecls%>
    <%outVarInits%>

    <%varInits%>

    <%bodyPart%>

    <%outVarCopy%>
    <%outVarAssign%>

    /*mahge: Free unwanted meomory allocated*/
    <%varFrees%>

    return<%if outVars then ' <%retVar%>' %>;
  }

  >>
end functionBodyParallelFunction;

template functionBodyKernelFunctionInterface(Function fn, Boolean inFunc)
 "Generates the body for a Modelica/MetaModelica function."
::=
match fn
case KERNEL_FUNCTION(__) then
  let()= System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */
  let fname = underscorePath(name)
  let &auxFunction = buffer ""

  let &varDecls = buffer ""
  let &varInits = buffer ""
  let &varFrees = buffer ""
  let _ = (listGet(outVars,1) |> var hasindex i1 fromindex 1 =>
      varInit(var, "", &varDecls, &varInits, &varFrees, &auxFunction) ; empty /* increase the counter! */
    )

  let outVarAssign = (List.restOrEmpty(outVars) |> var => varOutput(var))

  let cl_kernelVar = tempDecl("cl_kernel", &varDecls)
  let kernel_arg_number = '<%fname%>_arg_nr'

  let &kernelArgSets = buffer ""
  let _ = (functionArguments |> var =>
      setKernelArg_ith(var, &cl_kernelVar, &kernel_arg_number, &kernelArgSets)
    )
  let _ = (outVars |> var =>
      setKernelArg_ith(var, &cl_kernelVar, &kernel_arg_number, &kernelArgSets)
    )

  let defines = (List.restOrEmpty(outVars) |> var as VARIABLE(__) => '#define <%contextCref(name,contextFunction,&auxFunction)%> (*out<%contextCref(name,contextFunction,&auxFunction)%>)' ;separator="\n")
  let undefines = (List.restOrEmpty(outVars) |> var as VARIABLE(__) => '#undef <%contextCref(name,contextFunction,&auxFunction)%>' ;separator="\n")

  <<

  <%functionHeaderKernelFunctionInterfacePrototype(fname, functionArguments, outVars)%>
  {
  <%defines%>

    <%varDecls%>

    <%varInits%>

    /* functionBodyKernelFunctionInterface : <%fname%> Kernel creation and execution */
    int <%kernel_arg_number%> = 0;
    <%cl_kernelVar%> = ocl_create_kernel(omc_ocl_program, "omc_<%fname%>");
    <%kernelArgSets%>
    ocl_execute_kernel(<%cl_kernelVar%>);
    clReleaseKernel(<%cl_kernelVar%>);
    /*functionBodyKernelFunctionInterface : <%fname%> kernel execution ends here.*/

    <%outVarAssign%>

    <%varFrees%>

    <%match outVars
       case {} then 'return;'
       case var::_ then 'return <%funArgName(var)%>;'
    %>

  <%undefines%>
  }

  >>

end functionBodyKernelFunctionInterface;

template setKernelArg_ith(Variable var, Text &KernelName, Text &argNr, Text &parVarList /*BUFPA*/)
::=
let &auxFunction = buffer ""
match var
//function args will have nill instdims even if they are arrays. handled here
case var as VARIABLE(ty=T_ARRAY(__),parallelism=PARGLOBAL(__)) then
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.data); ++<%argNr%>; <%\n%>'
  let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.info_dev); ++<%argNr%>; <%\n%>'
  ""
case var as VARIABLE(ty=T_ARRAY(__),parallelism=PARLOCAL(__)) then
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  // Increment twice. Both data and info set in the function
  // let &parVarList += 'ocl_set_local_array_kernel_arg(<%KernelName%>, <%argNr%>, &<%varName%>); ++<%argNr%>; ++<%argNr%>; <%\n%>'
  let &parVarList += 'ocl_set_local_kernel_arg(<%KernelName%>, <%argNr%>, sizeof(modelica_<%expTypeShort(var.ty)%>) * device_array_nr_of_elements(&<%varName%>)); ++<%argNr%>; <%\n%>'
  let &parVarList += 'ocl_set_local_kernel_arg(<%KernelName%>, <%argNr%>, sizeof(modelica_integer) * (<%varName%>.info[0]+1)*sizeof(modelica_integer)); ++<%argNr%>; <%\n%>'
  ""
case var as VARIABLE(__) then
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  if instDims then
    let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.data); ++<%argNr%>; <%\n%>'
    let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.info_dev); ++<%argNr%>; <%\n%>'
  ""
  else
    let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>); ++<%argNr%>; <%\n%>'
  ""
end setKernelArg_ith;


template setKernelArgFormTupleLoopVars_ith(tuple<DAE.ComponentRef,builtin.SourceInfo> tupleVar, Text &KernelName, Text &argNr, Text &parVarList, Context context /*BUFPA*/)
::=
match tupleVar
//function args will have nill instdims even if they are arrays. handled here
case tupleVar as ((cref as CREF_IDENT(identType = T_ARRAY(__)),_)) then
  let varName = contextArrayCref(cref,context)
  let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.data); ++<%argNr%>; <%\n%>'
  let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>.info_dev); ++<%argNr%>; <%\n%>'
  ""
case tupleVar as ((cref as CREF_IDENT(__),_)) then
  let varName = contextArrayCref(cref,context)
  let &parVarList += 'ocl_set_kernel_arg(<%KernelName%>, <%argNr%>, <%varName%>); ++<%argNr%>; <%\n%>'
  ""
end setKernelArgFormTupleLoopVars_ith;


template functionBodyExternalFunction(Function fn, Boolean inFunc, Boolean isSimulation)
 "Generates the body for an external function (just a wrapper)."
::=
match fn
case efn as EXTERNAL_FUNCTION(__) then
  let()= System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */
  let fname = underscorePath(name)
  let retType = if outVars then '<%fname%>_rettype' else "void"
  let &preExp = buffer ""
  let &varDecls = buffer ""
  let &varFrees = buffer ""
  let &outputAlloc = buffer ""
  let &auxFunction = buffer ""
  let callPart = extFunCall(fn, &preExp, &varDecls, &auxFunction)
  let _ = ( outVars |> var =>
            varInit(var, "", &varDecls, &outputAlloc, &varFrees, &auxFunction)
            ; empty /* increase the counter! */ )

  let outVarAssign = (List.restOrEmpty(outVars) |> var => varOutput(var))

  let &varDecls += addRootsTempArray()
  let boxedFn = functionBodyBoxed(fn, isSimulation)
  let fnBody = <<
  <%auxFunction%>
  <%functionPrototype(fname, funArgs, outVars, false, visibility, isSimulation)%>
  {
    <%varDecls%>
    <%modelicaLine(info)%>
    <%outputAlloc%>
    <%preExp%>
    <%callPart%>
    <%outVarAssign%>
    <%match outVars
       case {} then 'return;'
       case v::_ then 'return <%funArgName(v)%>;'
    %>
  }
  >>
  <<
  <% if dynamicLoad then
  <<
  ptrT_<%extFunctionName(extName, language)%> ptr_<%extFunctionName(extName, language)%>=NULL;
  >> %>
  <%fnBody%>
  <% if inFunc then generateInFunc(fname, funArgs, outVars) %>
  <%boxedFn%>
  >>
end functionBodyExternalFunction;


template functionBodyRecordConstructor(Function fn, Boolean isSimulation)
 "Generates the body for a record constructor."
::=
match fn
case RECORD_CONSTRUCTOR(__) then
  let()= System.tmpTickReset(1)
  let &varDecls = buffer ""
  let &varInits = buffer ""
  let &varFrees = buffer ""
  let &auxFunction = buffer ""
  let fname = underscorePath(name)
  let structType = '<%fname%>'
  let structVar = tempDecl(structType, &varDecls)
  let _ = (locals |> var =>
      varInitRecord(var, structVar, &varDecls, &varInits, &auxFunction) ; empty /* increase the counter! */
    )
  let boxedFn = functionBodyBoxed(fn, isSimulation)
  <<
  <%auxFunction%>
  <%fname%> omc_<%fname%>(threadData_t *threadData<%funArgs |> VARIABLE(__) => ', <%expTypeArrayIf(ty)%> <%crefStr(name)%>'%>)
  {
    <%varDecls%>
    <%varInits%>
    <%funArgs |> VARIABLE(__) => '<%structVar%>._<%crefStr(name)%> = <%crefStr(name)%>;' ;separator="\n"%>
    return <%structVar%>;
  }

  <%boxedFn%>
  >>
end functionBodyRecordConstructor;

template varInitRecord(Variable var, String prefix, Text &varDecls, Text &varInits, Text &auxFunction)
 "Generates code to initialize variables.
  Does not return anything: just appends declarations to buffers."
::=
match var
case var as VARIABLE(parallelism = NON_PARALLEL(__)) then
  let varName = '<%prefix%>._<%crefToCStr(var.name)%>'
  let &varInits += initRecordMembers(var, &auxFunction)
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let defaultAlloc = 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
    let defaultValue = varAllocDefaultValue(var, "", varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
    let &varInits += defaultValue
    ""
  else
    (match var.value
    case SOME(exp) then
      let defaultValue = '<%varName%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
      let &varInits += defaultValue

      " "
    else
      "")

case var as FUNCTION_PTR(__) then
  ""
else error(sourceInfo(), 'Unknown local variable type in record')
end varInitRecord;

template functionBodyBoxed(Function fn, Boolean isSimulation)
 "Generates code for a boxed version of a function. Extracts the needed data
  from a function and calls functionBodyBoxedImpl"
::=
  let fname = match fn
  case FUNCTION(__)
  case EXTERNAL_FUNCTION(__)
  case RECORD_CONSTRUCTOR(__) then
    underscorePath(name)
  <<
  <%
  match fn
  case FUNCTION(__) then if not isBoxedFunction(fn) then functionBodyBoxedImpl(name, functionArguments, outVars, visibility, isSimulation)
  case EXTERNAL_FUNCTION(__) then if not isBoxedFunction(fn) then functionBodyBoxedImpl(name, funArgs, outVars, visibility, isSimulation)
  case RECORD_CONSTRUCTOR(__) then boxRecordConstructor(fn, isSimulation)
  %>
  >>
end functionBodyBoxed;

template functionBodyBoxedImpl(Absyn.Path name, list<Variable> funargs, list<Variable> outvars, SCode.Visibility visibility, Boolean isSimulation)
 "Helper template for functionBodyBoxed, does all the real work."
::=
  let() = System.tmpTickReset(1)
  let()= System.tmpTickResetIndex(0,1) /* Boxed array indices */
  let fname = underscorePath(name)
  let retTypeBoxed = if outvars then 'modelica_metatype' else "void"
  let &varDecls = buffer ""
  let &varBox = buffer ""
  let &varUnbox = buffer ""
  let &auxFunction = buffer ""
  let args = (funargs |> arg => (", " + funArgUnbox(arg, &varDecls, &varBox, &auxFunction)))
  let &varBoxIgnore = buffer ""
  let &outputAllocIgnore = buffer ""
  let &varFreesIgnore = buffer ""
  let &auxFunctionIgnore = buffer ""
  let outputs = ( List.restOrEmpty(outvars) |> var hasindex i1 fromindex 1 =>
    match var
      case v as VARIABLE(__) then
        if mmcConstructorType(liftArrayListExp(v.ty,v.instDims)) then
          let _ = varInit(var, "", &varDecls, &outputAllocIgnore, &varFreesIgnore, &auxFunctionIgnore)
          ", &" + funArgName(var)
        else
          ", out" + funArgName(var)
      case FUNCTION_PTR(__) then ", out" + funArgName(var)
    ; empty
    )
  let retvar = (match outvars
    case {} then ""
    case (v as VARIABLE(__))::_ then
      let _ = varInit(v, "", &varDecls, &outputAllocIgnore, &varFreesIgnore, &auxFunctionIgnore)
      let out = ("out" + funArgName(v))
      let _ = funArgBox(out, funArgName(v), "", liftArrayListExp(v.ty,v.instDims), &varUnbox, &varDecls)
      (if mmcConstructorType(liftArrayListExp(v.ty,v.instDims)) then
        let &varDecls += 'modelica_metatype <%out%>;<%\n%>'
        out
      else
        funArgName(v))
    case v::_ then
      let _ = varInit(v, "", &varDecls, &outputAllocIgnore, &varFreesIgnore, &auxFunctionIgnore)
      funArgName(v)
    )
  let _ = (List.restOrEmpty(outvars) |> var as VARIABLE(__) =>
    let arg = funArgName(var)
    funArgBox('*out<%arg%>', arg, 'out<%arg%>', liftArrayListExp(var.ty,var.instDims), &varUnbox, &varDecls)
    ; separator="\n")
  let prototype = functionPrototype(fname, funargs, outvars, true, visibility, isSimulation)
  <<
  <%auxFunction%>
  <%prototype%>
  {
    <%varDecls%>
    <%addRootsTempArray()%>
    <%varBox%>
    <%match outvars case v::_ then '<%funArgName(v)%> = '%>omc_<%fname%>(threadData<%args%><%outputs%>);
    <%varUnbox%>
    <%match outvars case v::_ then 'return <%retvar%>;' else "return;"%>
  }
  >>
end functionBodyBoxedImpl;

template boxRecordConstructor(Function fn, Boolean isSimulation)
::=
let &auxFunction = buffer ""
match fn
case RECORD_CONSTRUCTOR(__) then
  let() = System.tmpTickReset(1)
  let fname = underscorePath(name)
  let retType = '<%fname%>_rettypeboxed'
  let funArgsStr = (funArgs |> var => match var
     case VARIABLE(__) then ", " + contextCref(name,contextFunction,&auxFunction)
     case FUNCTION_PTR(__) then ", " + name
     else error(sourceInfo(),"boxRecordConstructor:Unknown variable"))
  let start = daeExpMetaHelperBoxStart(incrementInt(listLength(funArgs), 1))
  <<
  <%if isSimulation then "" else match visibility case PROTECTED(__) then "PROTECTED_FUNCTION_STATIC "%>modelica_metatype boxptr_<%fname%>(threadData_t *threadData<%funArgs |> var => (", " + funArgBoxedDefinition(var))%>)
  {
    return mmc_mk_box<%start%>3, &<%fname%>__desc<%funArgsStr%>);
  }
  >>
end boxRecordConstructor;

template funArgUnbox(Variable var, Text &varDecls, Text &varBox, Text &auxFunction)
::=
match var
case VARIABLE(__) then
  let varName = contextCref(name,contextFunction,&auxFunction)
  unboxVariable(varName, ty, &varBox, &varDecls)
case FUNCTION_PTR(__) then // Function pointers don't need to be boxed.
  '_<%name%>'
end funArgUnbox;

template unboxVariable(String varName, Type varType, Text &preExp, Text &varDecls)
::=
match varType
case T_COMPLEX(complexClassType = EXTERNAL_OBJ(__))
case T_STRING(__)
case T_METATYPE(__)
case T_METARECORD(__)
case T_METAUNIONTYPE(__)
case T_METALIST(__)
case T_METAARRAY(__)
case T_METAPOLYMORPHIC(__)
case T_METAOPTION(__)
case T_METATUPLE(__)
case T_METABOXED(__) then varName
case T_COMPLEX(complexClassType = RECORD(__)) then
  unboxRecord(varName, varType, &preExp, &varDecls)
case T_ARRAY(__) then
  '*((base_array_t*)<%varName%>)'
else
  let shortType = mmcTypeShort(varType)
  let ty = 'modelica_<%shortType%>'
  let tmpVar = tempDecl(ty, &varDecls)
  let &preExp += '<%tmpVar%> = mmc_unbox_<%shortType%>(<%varName%>);<%\n%>'
  tmpVar
end unboxVariable;

template unboxRecord(String recordVar, Type ty, Text &preExp, Text &varDecls)
::=
match ty
case T_COMPLEX(complexClassType = RECORD(path = path), varLst = vars) then
  let tmpVar = tempDecl('<%underscorePath(path)%>', &varDecls)
  let &preExp += (vars |> TYPES_VAR(name = compname) hasindex offset fromindex 2 =>
    let varType = mmcTypeShort(ty)
    let untagTmp = tempDecl('modelica_metatype', &varDecls)
    //let offsetStr = incrementInt(i1, 1)
    let &unboxBuf = buffer ""
    let unboxStr = unboxVariable(untagTmp, ty, &unboxBuf, &varDecls)
    <<
    <%untagTmp%> = (MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%recordVar%>), <%offset%>)));
    <%unboxBuf%>
    <%tmpVar%>._<%compname%> = <%unboxStr%>;
    >>
    ;separator="\n")
  tmpVar
end unboxRecord;

template funArgBox(String outName, String varName, String condition, Type ty, Text &varUnbox, Text &varDecls)
 "Generates code to box a variable."
::=
  let constructorType = mmcConstructorType(ty)
  if constructorType then
    let constructor = mmcConstructor(ty, varName, &varUnbox, &varDecls)
    let &varUnbox += if condition then 'if (<%condition%>) { <%outName%> = <%constructor%>; }<%\n%>' else '<%outName%> = <%constructor%>;<%\n%>'
    outName
  else // Some types don't need to be boxed, since they're already boxed.
    let &varUnbox += '/* skip box <%varName%>; <%unparseType(ty)%> */<%\n%>'
    varName
end funArgBox;

template mmcConstructorType(Type type)
::=
  match type
  case T_INTEGER(__)
  case T_BOOL(__)
  case T_REAL(__)
  case T_ENUMERATION(__)
  case T_ARRAY(__)
  case T_COMPLEX(complexClassType = RECORD(__)) then 'modelica_metatype'
end mmcConstructorType;

template mmcConstructor(Type type, String varName, Text &preExp, Text &varDecls)
::=
  match type
  case T_INTEGER(__) then 'mmc_mk_icon(<%varName%>)'
  case T_BOOL(__) then 'mmc_mk_icon(<%varName%>)'
  case T_REAL(__) then 'mmc_mk_rcon(<%varName%>)'
  case T_STRING(__) then 'mmc_mk_string(<%varName%>)'
  case T_ENUMERATION(__) then 'mmc_mk_icon(<%varName%>)'
  case T_ARRAY(__) then 'mmc_mk_modelica_array(<%varName%>)'
  case T_COMPLEX(complexClassType = RECORD(path = path), varLst = vars) then
    let varCount = daeExpMetaHelperBoxStart(incrementInt(listLength(vars), 1))
    let varsStr = (vars |> var as TYPES_VAR(__) =>
      let tmp = tempDecl("modelica_metatype", &varDecls)
      let varname = '<%varName%>._<%name%>'
      ", " + funArgBox(tmp, varname, "", ty, &preExp, &varDecls)
      )
    'mmc_mk_box<%varCount%>3, &<%underscorePath(path)%>__desc<%varsStr%>)'
  case T_COMPLEX(__) then 'mmc_mk_box(<%varName%>)'
end mmcConstructor;

template readInVar(Variable var)
 "Generates code for reading a variable from inArgs."
::=
  let &auxFunction = buffer ""
  match var
  case VARIABLE(name=cr, ty=T_COMPLEX(complexClassType=RECORD(__))) then
    <<
    if (read_modelica_record(&inArgs, <%readInVarRecordMembers(ty, contextCref(cr,contextFunction,&auxFunction))%>)) return 1;
    >>
  case VARIABLE(name=cr, ty=T_STRING(__)) then
    <<
    if (read_<%expTypeArrayIf(ty)%>(&inArgs, <%if not acceptMetaModelicaGrammar() then "(char**)"%> &<%contextCref(name,contextFunction,&auxFunction)%>)) return 1;
    >>
  case VARIABLE(__) then
    <<
    if (read_<%expTypeArrayIf(ty)%>(&inArgs, &<%contextCref(name,contextFunction,&auxFunction)%>)) return 1;
    >>
end readInVar;


template readInVarRecordMembers(Type type, String prefix)
 "Helper to readInVar."
::=
match type
case T_COMPLEX(varLst=vl) then
  (vl |> subvar as TYPES_VAR(__) =>
    match ty case T_COMPLEX(__) then
      let newPrefix = '<%prefix%>._<%subvar.name%>'
      readInVarRecordMembers(ty, newPrefix)
    else
      '&(<%prefix%>._<%subvar.name%>)'
  ;separator=", ")
end readInVarRecordMembers;


template writeOutVar(Variable var)
 "Generates code for writing a variable to outVar."

::=
  match var
  case VARIABLE(ty=T_COMPLEX(complexClassType=RECORD(__))) then
    <<
    write_modelica_record(outVar, <%writeOutVarRecordMembers(ty, funArgName(var))%>);
    >>
  case VARIABLE(__) then

    <<
    write_<%varType(var)%>(outVar, &<%funArgName(var)%>);
    >>
end writeOutVar;


template writeOutVarRecordMembers(Type type, String prefix)
 "Helper to writeOutVar."
::=
match type
case T_COMPLEX(varLst=vl, complexClassType=n) then
  let basename = underscorePath(ClassInf.getStateName(n))
  let args = (vl |> subvar as TYPES_VAR(__) =>
      match ty case T_COMPLEX(__) then
        let newPrefix = '<%prefix%>._<%subvar.name%>'
        '<%expTypeRW(ty)%>, <%writeOutVarRecordMembers(ty, newPrefix)%>'
      else
        '<%expTypeRW(ty)%>, &(<%prefix%>._<%subvar.name%>)'
    ;separator=", ")
  <<
  &<%basename%>__desc<%if args then ', <%args%>'%>, TYPE_DESC_NONE
  >>
end writeOutVarRecordMembers;

template varInit(Variable var, String outStruct, Text &varDecls, Text &varInits, Text &varFrees, Text &auxFunction)
 "Generates code to initialize variables.
  Does not return anything: just appends declarations to buffers."
::=
match var
case var as VARIABLE(parallelism = NON_PARALLEL(__)) then
  let varName = contextCref(var.name,contextFunction,&auxFunction)
  let typ = varType(var)
  let initVar = match typ case "modelica_metatype"
                          case "modelica_string" then ' = NULL'
                          else ''
  let &varDecls += if not outStruct then '<%typ%> <%varName%><%initVar%>;<%\n%>' //else ""
  let varName = contextCref(var.name,contextFunction,&auxFunction)
  let &varInits += initRecordMembers(var, &auxFunction)
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    (match var.ty
    case T_COMPLEX(__) then
      let defaultAlloc = 'alloc_generic_array(&<%varName%>, sizeof(<%expTypeShort(var.ty)%>), <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
      (match var.value
      case SOME(exp) then
        let defaultValue = varAllocDefaultValue(var, outStruct, varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
        let &varInits += defaultValue
        ""
      else
        let &varInits += defaultAlloc
        "")
    else
      let defaultAlloc = 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
      let defaultValue = varAllocDefaultValue(var, outStruct, varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
      let &varInits += defaultValue
      "")
  else
    (match var.value
    case SOME(exp) then
      let defaultValue = '<%contextCref(var.name,contextFunction,&auxFunction)%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
      let &varInits += defaultValue

      " "
    else
      "")

//mahge: OpenCL/CUDA GPU variables.
case var as VARIABLE(__) then
  parVarInit(var, outStruct, &varDecls, &varInits, &varFrees, &auxFunction)

case var as FUNCTION_PTR(__) then
  let &varDecls += 'modelica_fnptr _<%name%>;<%\n%>'
  let varInitText = (match defaultValue
     case SOME(exp) then
     let v = daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
     '_<%name%> = <%v%>;<%\n%>')
  let &varInits += varInitText
  ""
else error(sourceInfo(), 'Unknown local variable type')
end varInit;

/* ParModelica Extension. */
template parVarInit(Variable var, String outStruct, Text &varDecls, Text &varInits, Text &varFrees, Text &auxFunction)
 "Generates code to initialize ParModelica variables.
  Does not return anything: just appends declarations to buffers."
::=
match var
case var as VARIABLE(parallelism = PARGLOBAL(__)) then
  let varName = '<%contextCref(var.name, contextFunction, &auxFunction)%>'

  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")

  if instDims then
    let &varDecls += 'device_<%expTypeShort(var.ty)%>_array <%varName%>;<%\n%>'
    let defaultAlloc = 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
    let defaultValue = varAllocDefaultValue(var, outStruct, varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
    let &varInits += defaultValue

    let &varFrees += 'free_device_array(&<%varName%>);<%\n%>'
    ""
  else
    (match var.value
    case SOME(exp) then
      let &varDecls += '<%varType(var)%> <%varName%>;<%\n%>'
      let defaultValue = '<%contextCref(var.name,contextFunction,&auxFunction)%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
      let &varInits += defaultValue

      " "
    else
    let &varDecls += '<%varType(var)%> <%varName%>;<%\n%>'
      "")

case var as VARIABLE(parallelism = PARLOCAL(__)) then
  let varName = '<%contextCref(var.name, contextFunction, &auxFunction)%>'

  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let &varDecls += 'device_local_<%expTypeShort(var.ty)%>_array <%varName%>;<%\n%>'
    let defaultAlloc = 'alloc_device_local_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
    let defaultValue = varAllocDefaultValue(var, outStruct, varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
    let &varInits += defaultValue

    // let &varFrees += 'free_device_array(&<%varName%>);<%\n%>'
    ""
  else
    (match var.value
    case SOME(exp) then
      let &varDecls += '<%varType(var)%> <%varName%>;<%\n%>'
      let defaultValue = '<%contextCref(var.name,contextFunction,&auxFunction)%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
      let &varInits += defaultValue

      " "
    else
    let &varDecls += '<%varType(var)%> <%varName%>;<%\n%>'
      "")

else
  let &varDecls += '#error Unknown parallel variable type<%\n%>'
  error(sourceInfo(), 'parVarInit:error Unknown parallel variable type')
end parVarInit;

template varInitParallel(Variable var, String outStruct, Integer i, Text &varDecls, Text &varInits, Text &varFrees, Text &auxFunction)
 "Generates code to initialize variables in PARALLEL FUNCTIONS.
  Does not return anything: just appends declarations to buffers."
::=
match var
case var as VARIABLE(__) then
  let &varDecls += if not outStruct then '<%varType(var)%> <%contextCref(var.name, contextFunction, &auxFunction)%>;<%\n%>' //else ""
  let varName = if outStruct then '<%outStruct%>.targ<%i%>' else '<%contextCref(var.name, contextFunction, &auxFunction)%>'
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let defaultAlloc = 'alloc_<%expTypeShort(var.ty)%>_array_c99_<%listLength(instDims)%>(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>, memory_state);<%\n%>'
    let defaultValue = varAllocDefaultValue(var, outStruct, varName, defaultAlloc, &varDecls, &varInits, &auxFunction)
    let &varInits += defaultValue
    " "
  else
    (match var.value
    case SOME(exp) then
      let defaultValue = '<%contextCref(var.name,contextFunction,&auxFunction)%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
      let &varInits += defaultValue
      " "
    else
      "")
case var as FUNCTION_PTR(__) then
  ""
else
  let &varDecls += '#error Unknown local variable type<%\n%>'
  error(sourceInfo(), 'varInitParallel:error Unknown local variable type')
end varInitParallel;


template varAllocDefaultValue(Variable var, String outStruct, String lhsVarName, Text allocNoDefault, Text &varDecls, Text &varInits, Text &auxFunction)
::=
match var
case var as VARIABLE(__) then
  match value
  case SOME(CREF(componentRef = cr)) then
    'copy_<%expTypeShort(var.ty)%>_array(<%contextCref(cr,contextFunction,&auxFunction)%>, &<%lhsVarName%>);<%\n%>'
  case SOME(arr as ARRAY(ty = T_ARRAY(ty = T_COMPLEX(complexClassType = record_state)))) then
    let &varInits += allocNoDefault
    let varName = contextCref(var.name,contextFunction,&auxFunction)
    let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
    let &preExp = buffer ""
    let params = (arr.array |> e hasindex i1 fromindex 1 =>
      let prefix = if arr.scalar then '(<%expTypeFromExpModelica(e)%>)' else '&'
      '(*((<%rec_name%>*)generic_array_element_addr(&<%varName%>, sizeof(<%rec_name%>), 1, <%i1%>))) = <%prefix%><%daeExp(e, contextFunction, &preExp, &varDecls, &auxFunction)%>;'
    ;separator="\n")
    <<
    <%preExp%>
    <%params%>
    >>
  case SOME(arr as ARRAY(__)) then
    let arrayExp = '<%daeExp(arr, contextFunction, &varInits, &varDecls, &auxFunction)%>'
    'copy_<%expTypeShort(var.ty)%>_array(<%arrayExp%>, &<%lhsVarName%>);<%\n%>'
  case SOME(exp) then
    '<%lhsVarName%> = <%daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)%>;<%\n%>'
  else
    let &varInits += allocNoDefault
    ""
end varAllocDefaultValue;

template varOutput(Variable var)
 "Generates code to copy result value from a function to dest."
::=
  match var
  case FUNCTION_PTR(__) then
    'if (out<%funArgName(var)%>) { *out<%funArgName(var)%> = (modelica_fnptr)<%funArgName(var)%>; }<%\n%>'
  case VARIABLE(ty=T_ARRAY(__)) then
    // If the dim_size is NULL, the output is an array with unknown dimensions. Copy the array.
    'if (out<%funArgName(var)%>) { if (out<%funArgName(var)%>->dim_size == NULL) {copy_<%expTypeShort(var.ty)%>_array(<%funArgName(var)%>, out<%funArgName(var)%>);} else {copy_<%expTypeShort(var.ty)%>_array_data(<%funArgName(var)%>, out<%funArgName(var)%>);} }<%\n%>'
  case VARIABLE(__) then
    /*Seems like we still get an array var with the wrong type here. It have instdims though >_<. TODO I guess*/
    if instDims then
      'if (out<%funArgName(var)%>) { if (out<%funArgName(var)%>->dim_size == NULL) {copy_<%expTypeShort(var.ty)%>_array(<%funArgName(var)%>, out<%funArgName(var)%>);} else {copy_<%expTypeShort(var.ty)%>_array_data(<%funArgName(var)%>, out<%funArgName(var)%>);} }<%\n%>'
    else
    'if (out<%funArgName(var)%>) { *out<%funArgName(var)%> = <%funArgName(var)%>; }<%\n%>'
  else error(sourceInfo(), 'varOutput:error Unknown variable type as output')
end varOutput;

template varOutputParallel(Variable var, String dest, Integer ix, Text &varDecls,
          Text &varInits, Text &varCopy, Text &varAssign, Text &auxFunction)
 "Generates code to copy result value from a function to dest in a Parallel function."
::=
match var
/* The storage size of arrays is known at call time, so they can be allocated
 * before set_memory_state. Strings are not known, so we copy them, etc...
 */
case var as VARIABLE(ty = T_STRING(__)) then
    if not acceptMetaModelicaGrammar() then
      // We need to strdup() all strings, then allocate them on the memory pool again, then free the temporary string
      let &varCopy += 'String Variables not Allowed in ParModelica.'
      let &varAssign +=
        <<
           String Variables not Allowed in ParModelica.
        >>
      ""
    else
      let &varAssign += 'How did you get here??'
      ""
case var as VARIABLE(parallelism = PARGLOBAL(__)) then
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array_c99_<%listLength(instDims)%>(&<%dest%>.c<%ix%>, <%listLength(instDims)%>, <%instDimsInit%>, memory_state);<%\n%>'
    let &varAssign += 'copy_<%expTypeShort(var.ty)%>_array_data(<%contextCref(var.name,contextFunction, &auxFunction)%>, &<%dest%>.c<%ix%>);<%\n%>'
    ""
  else
  let &varInits += '<%dest%>.c<%ix%> = ocl_device_alloc(sizeof(modelica_<%expTypeShort(var.ty)%>));<%\n%>'
  let &varAssign += 'copy_assignment_helper_<%expTypeShort(var.ty)%>(&<%dest%>.c<%ix%>, &<%contextCref(var.name,contextFunction,&auxFunction)%>);<%\n%>'
  ""

case var as VARIABLE(parallelism = PARLOCAL(__)) then
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array_c99_<%listLength(instDims)%>(&<%dest%>.c<%ix%>, <%listLength(instDims)%>, <%instDimsInit%>, memory_state);<%\n%>'
    let &varAssign += 'copy_<%expTypeShort(var.ty)%>_array_data(<%contextCref(var.name, contextFunction, &auxFunction)%>, &<%dest%>.c<%ix%>);<%\n%>'
    ""
  else
  let &varInits += 'LOCAL HERE!! <%dest%>.c<%ix%> = ocl_device_alloc(sizeof(modelica_<%expTypeShort(var.ty)%>));<%\n%>'
  let &varAssign += 'LOCAL HERE!! copy_assignment_helper_<%expTypeShort(var.ty)%>(&<%dest%>.c<%ix%>, &<%contextCref(var.name,contextFunction,&auxFunction)%>);<%\n%>'
  ""

case var as VARIABLE(__) then
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
    let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array_c99_<%listLength(instDims)%>(&<%dest%>.c<%ix%>, <%listLength(instDims)%>, <%instDimsInit%>, memory_state);<%\n%>'
    let &varAssign += 'copy_<%expTypeShort(var.ty)%>_array_data(<%contextCref(var.name,contextFunction,&auxFunction)%>, &<%dest%>.c<%ix%>);<%\n%>'
    ""
  else
    let &varInits += initRecordMembers(var, &auxFunction)
    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
    ""
case var as FUNCTION_PTR(__) then
    let &varAssign += '<%dest%>.c<%ix%> = (modelica_fnptr) _<%var.name%>;<%\n%>'
    ""
end varOutputParallel;

template varOutputKernelInterface(Variable var, String dest, Integer ix, Text &varDecls,
          Text &varInits, Text &varCopy, Text &varAssign, Text &auxFunction)
 "Generates code to copy result value from a function to dest."
::=
match var
case var as VARIABLE(parallelism = PARGLOBAL(__)) then
  let &varDecls += '<%varType(var)%> <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
  let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'

    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
    ""
  else
    let &varInits += '<%varName%> = ocl_device_alloc(sizeof(modelica_<%expTypeShort(var.ty)%>));<%\n%>'
    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
  ""

case var as VARIABLE(parallelism = PARLOCAL(__)) then
  let &varDecls += '<%varType(var)%> <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
  let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'

    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
    ""
  else
    let &varInits += '<%varName%> = ocl_device_alloc(sizeof(modelica_<%expTypeShort(var.ty)%>));<%\n%>'
    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
  ""

case var as VARIABLE(__) then
  let &varDecls += '<%varType(var)%> <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
  let varName = '<%contextCref(var.name,contextFunction,&auxFunction)%>'
  let instDimsInit = (instDims |> exp =>
      daeExp(exp, contextFunction, &varInits, &varDecls, &auxFunction)
    ;separator=", ")
  if instDims then
  let &varInits += 'alloc_<%expTypeShort(var.ty)%>_array(&<%varName%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'

    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
    ""
  else
    let &varInits += initRecordMembers(var, &auxFunction)
    let &varAssign += '<%dest%>.c<%ix%> = <%contextCref(var.name,contextFunction,&auxFunction)%>;<%\n%>'
    ""
case var as FUNCTION_PTR(__) then
    let &varAssign += '<%dest%>.c<%ix%> = (modelica_fnptr) _<%var.name%>;<%\n%>'
    ""
end varOutputKernelInterface;

template initRecordMembers(Variable var, Text &auxFunction)
::=
match var
case VARIABLE(ty = T_COMPLEX(complexClassType = RECORD(__))) then
  let varName = contextCref(name,contextFunction,&auxFunction)
  (ty.varLst |> v => recordMemberInit(v, varName) ;separator="\n")
end initRecordMembers;

template recordMemberInit(Var v, Text varName)
::=
match v
case TYPES_VAR(ty = T_ARRAY(__)) then
  let arrayType = expType(ty, true)
  let dims = (ty.dims |> dim => dimension(dim) ;separator=", ")
  'alloc_<%arrayType%>(&<%varName%>._<%name%>, <%listLength(ty.dims)%>, <%dims%>);'
end recordMemberInit;

template extVarName(ComponentRef cr)
::= '_<%crefToMStr(appendStringFirstIdent("_ext", cr))%>'
end extVarName;

template extFunCall(Function fun, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates the call to an external function."
::=
match fun
case EXTERNAL_FUNCTION(__) then
  match language
  case "C" then extFunCallC(fun, &preExp, &varDecls, &auxFunction)
  case "FORTRAN 77" then extFunCallF77(fun, &preExp, &varDecls, &auxFunction)
end extFunCall;

template extFunCallC(Function fun, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates the call to an external C function."
::=
match fun
case EXTERNAL_FUNCTION(__) then
  /* adpro: 2011-06-24 do vardecls -> extArgs as there might be some sets in there! */
  let &preExp += (List.union(extArgs, extArgs) |> arg => extFunCallVardecl(arg, &varDecls, &auxFunction) ;separator="\n")
  let _ = (biVars |> bivar => extFunCallBiVar(bivar, &preExp, &varDecls, &auxFunction) ;separator="\n")
  let fname = if dynamicLoad then 'ptr_<%extFunctionName(extName, language)%>' else '<%extName%>'
  let dynamicCheck = if dynamicLoad then
  <<
  if(<%fname%>==NULL)
  {
    FILE_INFO info = {<%infoArgs(info)%>};
    omc_terminate(info, "dynamic external function <%extFunctionName(extName, language)%> not set!");
  } else
  >>
    else ''
  let args = (extArgs |> arg => extArg(arg, &preExp, &varDecls, &auxFunction) ;separator=", ")
  let returnAssign = match extReturn case SIMEXTARG(cref=c) then
      '<%extVarName(c)%> = '
    else
      ""
  <<
  <%match extReturn case SIMEXTARG(__) then extFunCallVardecl(extReturn, &varDecls, &auxFunction)%>
  <%dynamicCheck%>
  <%returnAssign%><%fname%>(<%args%>);
  <%extArgs |> arg => extFunCallVarcopy(arg, &auxFunction) ;separator="\n"%>
  <%match extReturn case SIMEXTARG(__) then extFunCallVarcopy(extReturn, &auxFunction)%>
  >>
end extFunCallC;

template extFunCallF77(Function fun, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates the call to an external Fortran 77 function."
::=
match fun
case EXTERNAL_FUNCTION(__) then
  /* adpro: 2011-06-24 do vardecls -> bivar -> extArgs as there might be some sets in there! */
  let &varDecls += '/* extFunCallF77: varDecs */<%\n%>'
  let varDecs = (List.union(extArgs, extArgs) |> arg => extFunCallVardeclF77(arg, &varDecls, &auxFunction) ;separator="\n")
  let &varDecls += '/* extFunCallF77: biVarDecs */<%\n%>'
  let &preExp += '/* extFunCallF77: biVarDecs */<%\n%>'
  let biVarDecs = (biVars |> arg => extFunCallBiVarF77(arg, &preExp, &varDecls, &auxFunction) ;separator="\n")
  let &varDecls += '/* extFunCallF77: args */<%\n%>'
  let &preExp += '/* extFunCallF77: args */<%\n%>'
  let args = (extArgs |> arg => extArgF77(arg, &preExp, &varDecls, &auxFunction) ;separator=", ")
  let &preExp += '/* extFunCallF77: end args */<%\n%>'
  let returnAssign = match extReturn case SIMEXTARG(cref=c) then
      '<%extVarName(c)%> = '
    else
      ""
  <<
  <%varDecs%>
  <%biVarDecs%>
  /* extFunCallF77: extReturn */
  <%match extReturn case SIMEXTARG(__) then extFunCallVardeclF77(extReturn, &varDecls, &auxFunction)%>
  /* extFunCallF77: CALL */
  <%returnAssign%><%extName%>_(<%args%>);
  /* extFunCallF77: copy args */
  <%List.union(extArgs,extArgs) |> arg => extFunCallVarcopyF77(arg, &auxFunction) ;separator="\n"%>
  /* extFunCallF77: copy return */
  <%match extReturn case SIMEXTARG(__) then extFunCallVarcopyF77(extReturn, &auxFunction)%>
  >>

end extFunCallF77;

template extFunCallVardecl(SimExtArg arg, Text &varDecls, Text &auxFunction)
 "Helper to extFunCall."
::=
  match arg
  case SIMEXTARG(isInput = true, isArray = true, type_ = ty, cref = c) then
    match expTypeShort(ty)
    case "integer" then
      'pack_integer_array(&<%contextCref(c,contextFunction,&auxFunction)%>);'
    else ""
  case SIMEXTARG(isInput = false, isArray = true, type_ = ty, cref = c) then
    match expTypeShort(ty)
    case "string" then
      'fill_string_array(&<%contextCref(c,contextFunction,&auxFunction)%>, mmc_string_uninitialized);<%\n%>'
    else ""
  case SIMEXTARG(isInput=true, isArray=false, type_=ty, cref=c) then
    match ty
    case T_STRING(__) then
      ""
    case T_FUNCTION_REFERENCE_VAR(__) then
      (match c
      case CREF_IDENT(__) then
        let &varDecls += 'modelica_fnptr <%extVarName(c)%>;<%\n%>'
        <<
        if (MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(_<%ident%>), 2))) {
          <%generateThrow()%> /* The FFI does not allow closures */
        }
        <%extVarName(c)%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(_<%ident%>), 1));
        >>
      else
        error(sourceInfo(), 'Got function pointer that is not a CREF_IDENT: <%crefStr(c)%>, <%unparseType(ty)%>'))
    else
      let &varDecls += '<%extType(ty,true,false)%> <%extVarName(c)%>;<%\n%>'
      <<
      <%extVarName(c)%> = (<%extType(ty,true,false)%>)<%contextCref(c,contextFunction,&auxFunction)%>;
      >>
  case SIMEXTARG(outputIndex=oi, isArray=false, type_=ty, cref=c) then
    match oi case 0 then
      ""
    else
      let &varDecls += '<%extType(ty,true,false)%> <%extVarName(c)%>;<%\n%>'
      ""
end extFunCallVardecl;

template extFunCallVardeclF77(SimExtArg arg, Text &varDecls, Text &auxFunction)
::=
  match arg
  case SIMEXTARG(isInput = true, isArray = true, type_ = ty, cref = c) then
    let &varDecls += '<%expTypeArrayIf(ty)%> <%extVarName(c)%>;<%\n%>'
    'convert_alloc_<%expTypeArray(ty)%>_to_f77(&<%contextCref(c,contextFunction,&auxFunction)%>, &<%extVarName(c)%>);'
  case ea as SIMEXTARG(outputIndex = oi, isArray = ia, type_= ty, cref = c) then
    match oi case 0 then "" else
      match ia
        case false then
          let default_val = typeDefaultValue(ty)
          let default_exp = if ea.hasBinding then "" else match default_val case "" then "" else ' = <%default_val%>'
          let &varDecls += '<%extTypeF77(ty,false)%> <%extVarName(c)%><%default_exp%>;<%\n%>'
          ""
        else
          let &varDecls += '<%expTypeArrayIf(ty)%> <%extVarName(c)%>;<%\n%>'
          'convert_alloc_<%expTypeArray(ty)%>_to_f77(&<%contextCref(c,contextFunction,&auxFunction)%>, &<%extVarName(c)%>);'
  case SIMEXTARG(type_ = ty, cref = c) then
    let &varDecls += '<%extTypeF77(ty,false)%> <%extVarName(c)%>;<%\n%>'
    ""
end extFunCallVardeclF77;

template boolStrC(Boolean v)
::= if v then '1' else '0'
end boolStrC;

template typeDefaultValue(DAE.Type ty)
::=
  match ty
  case ty as T_INTEGER(__) then '0'
  case ty as T_REAL(__) then '0.0'
  case ty as T_BOOL(__) then boolStrC(false)
  case ty as T_STRING(__) then '0' /* Always segfault is better than only sometimes segfault :) */
  else ""
end typeDefaultValue;

template extFunCallBiVar(Variable var, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match var
  case var as VARIABLE(__) then
    let var_name = extVarName(name)
    let &varDecls += '<%varType(var)%> <%var_name%>;<%\n%>'
    let defaultValue = match value
      case SOME(v) then
        daeExp(v, contextFunction, &preExp, &varDecls, &auxFunction)
      else ""
    let &preExp += if defaultValue then '<%var_name%> = <%defaultValue%>;<%\n%>'
    ""
end extFunCallBiVar;

template extFunCallBiVarF77(Variable var, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match var
  case var as VARIABLE(__) then
    let var_name = contextCref(name,contextFunction,&auxFunction)
    let &varDecls += '<%varType(var)%> <%var_name%>;<%\n%>'
    let &varDecls += '<%varType(var)%> <%extVarName(name)%>;<%\n%>'
    let defaultValue = match value
      case SOME(v) then
        '<%daeExp(v, contextFunction, &preExp, &varDecls, &auxFunction)%>'
      else ""
    let instDimsInit = (instDims |> exp =>
        daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction) ;separator=", ")
    if instDims then
      let type = expTypeArray(var.ty)
      let &preExp += 'alloc_<%type%>(&<%var_name%>, <%listLength(instDims)%>, <%instDimsInit%>);<%\n%>'
      let &preExp += if defaultValue then 'copy_<%type%>(<%defaultValue%>, &<%var_name%>);<%\n%>' else ''
      let &preExp += 'convert_alloc_<%type%>_to_f77(&<%var_name%>, &<%extVarName(name)%>);<%\n%>'
      ""
    else
      let &preExp += if defaultValue then '<%var_name%> = <%defaultValue%>;<%\n%>' else ''
      ""
end extFunCallBiVarF77;

template extFunCallVarcopy(SimExtArg arg, Text &auxFunction)
 "Helper to extFunCall."
::=
match arg
case SIMEXTARG(outputIndex=0) then ""
case SIMEXTARG(outputIndex=oi, isArray=true, cref=c, type_=ty) then
  match expTypeShort(ty)
  case "integer" then
  'unpack_integer_array(&<%contextCref(c,contextFunction,&auxFunction)%>);'
  case "string" then
  'unpack_string_array(&<%contextCref(c,contextFunction,&auxFunction)%>, <%contextCref(c,contextFunction,&auxFunction)%>_c89);'
  else ""
case SIMEXTARG(outputIndex=oi, isArray=false, type_=ty, cref=c) then
    let cr = '<%extVarName(c)%>'
    <<
    <%contextCref(c,contextFunction,&auxFunction)%> = (<%expTypeModelica(ty)%>)<%
      match ty
          case T_STRING(__) then 'mmc_mk_scon(<%cr%>)'
          else cr%>;
    >>
end extFunCallVarcopy;

template extFunCallVarcopyF77(SimExtArg arg, Text &auxFunction)
 "Generates code to copy results from output variables into the out struct.
  Helper to extFunCallF77."
::=
match arg
case SIMEXTARG(outputIndex=oi, isArray=ai, type_=ty, cref=c) then
  match oi case 0 then
    ""
  else
    let outarg = contextCref(c,contextFunction,&auxFunction)
    let ext_name = extVarName(c)
    match ai
    case false then
      '<%outarg%> = (<%expTypeModelica(ty)%>)<%ext_name%>;<%\n%>'
    case true then
      'convert_alloc_<%expTypeArray(ty)%>_from_f77(&<%ext_name%>, &<%outarg%>);'
end extFunCallVarcopyF77;

template extArg(SimExtArg extArg, Text &preExp, Text &varDecls, Text &auxFunction)
 "Helper to extFunCall."
::=
  match extArg
  case SIMEXTARG(cref=c, outputIndex=oi, isArray=true, type_=t) then
    let name = contextCref(c,contextFunction,&auxFunction)
    let shortTypeStr = expTypeShort(t)
    let &varDecls += 'void *<%name%>_c89;<%\n%>'
    let &preExp += '<%name%>_c89 = (void*) data_of_<%shortTypeStr%>_c89_array(&(<%name%>));<%\n%>'
    '(<%extType(t,isInput,true)%>) <%name%>_c89'
  case SIMEXTARG(cref=c, isInput=ii, outputIndex=0, type_=t) then
    let cr = match t case T_STRING(__) then contextCref(c,contextFunction,&auxFunction) else extVarName(c)
    (match t case T_STRING(__) then 'MMC_STRINGDATA(<%cr%>)' else cr)
  case SIMEXTARG(cref=c, isInput=ii, outputIndex=oi, type_=t) then
    '&<%extVarName(c)%>'
  case SIMEXTARGEXP(__) then
    daeExternalCExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
  case SIMEXTARGSIZE(cref=c) then
    let typeStr = expTypeShort(type_)
    let name = contextCref(c,contextFunction, &auxFunction)
    let dim = daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
    'size_of_dimension_base_array(<%name%>, <%dim%>)'
end extArg;

template extArgF77(SimExtArg extArg, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match extArg
  case SIMEXTARG(cref=c, isArray=true, type_=t) then
    // Arrays are converted to fortran format that are stored in _ext-variables.
    'data_of_<%expTypeShort(t)%>_f77_array(&(<%extVarName(c)%>))'
  case SIMEXTARG(cref=c, outputIndex=oi, type_=T_INTEGER(__)) then
    // Always prefix fortran arguments with &.
    let suffix = if oi then "_ext"
    '(int*) &<%contextCref(c,contextFunction,&auxFunction)%><%suffix%>'
  case SIMEXTARG(cref=c, outputIndex=oi, type_ = T_STRING(__)) then
    // modelica_string SHOULD NOT BE PREFIXED by &!
    '(char*)MMC_STRINGDATA(<%contextCref(c,contextFunction,&auxFunction)%>)'
  case SIMEXTARG(cref=c, outputIndex=oi, type_=t) then
    // Always prefix fortran arguments with &.
    let suffix = if oi then "_ext"
    '&<%contextCref(c,contextFunction, &auxFunction)%><%suffix%>'
  case SIMEXTARGEXP(exp=exp, type_ = T_STRING(__)) then
    // modelica_string SHOULD NOT BE PREFIXED by &!
    let texp = daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
    let tvar = tempDecl(expTypeFromExpFlag(exp,8),&varDecls)
    let &preExp += '<%tvar%> = <%texp%>;<%\n%>'
    '(char*)MMC_STRINGDATA(<%tvar%>)'
  case SIMEXTARGEXP(__) then
    daeExternalF77Exp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
  case SIMEXTARGSIZE(cref=c) then
    // Fortran functions only takes references to variables, so we must store
    // the result from size_of_dimension_<type>_array in a temporary variable.
    let sizeVarName = tempSizeVarName(c, exp, &auxFunction)
    let sizeVar = tempDecl("int", &varDecls)
    let dim = daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
    let &preExp += '<%sizeVar%> = size_of_dimension_base_array(<%contextCref(c,contextFunction, &auxFunction)%>, <%dim%>);<%\n%>'
    '&<%sizeVar%>'
end extArgF77;

template tempSizeVarName(ComponentRef c, DAE.Exp indices, Text &auxFunction)

::=
  match indices
  case ICONST(__) then '<%contextCref(c,contextFunction,&auxFunction)%>_size_<%integer%>'
  else error(sourceInfo(), 'tempSizeVarName:UNHANDLED_EXPRESSION')
end tempSizeVarName;

template funStatement(Statement stmt, Text &varDecls, Text &auxFunction)
 "Generates function statements."
::=
  match stmt
  case ALGORITHM(__) then
    (statementLst |> stmt =>
      algStatement(stmt, contextFunction, &varDecls, &auxFunction)
    ;separator="\n")
  else
    error(sourceInfo(), 'funStatement:NOT IMPLEMENTED FUN STATEMENT')
end funStatement;

template parModelicafunStatement(Statement stmt, Text &varDecls, Text &auxFunction)
 "Generates function statements With PARALLEL context. Similar to Function context.
 Except in some cases like assignments."
::=
  match stmt
  case ALGORITHM(__) then
    (statementLst |> stmt =>
      algStatement(stmt, contextParallelFunction, &varDecls, &auxFunction)
    ;separator="\n")
  else
    error(sourceInfo(), 'parModelicafunStatement:NOT IMPLEMENTED FUN STATEMENT')
end parModelicafunStatement;

template extractParFors(Statement stmt, Text &varDecls, Text &auxFunction)
 "Generates bodies of parfor loops to the kernel file.
 The sequential C operations needed to implement the parallel
 for loop will be handled by the normal funStatment template."
::=
  match stmt
  case ALGORITHM(__) then
    (statementLst |> stmt =>
      extractParFors_impl(stmt, contextParallelFunction, &varDecls, &auxFunction)
    ;separator="\n")
  else
    error(sourceInfo(), 'extractParFors:NOT IMPLEMENTED FUN STATEMENT')
end extractParFors;


template extractParFors_impl(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an algorithm statement."
::=
  match stmt
  case s as STMT_PARFOR(__)         then algStmtParForBody(s, contextParallelFunction, &varDecls, &auxFunction)
end extractParFors_impl;



template algStatement(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an algorithm statement."
::=
  match System.tmpTickIndexReserve(1, 0) /* Remember the old tmpTick */
  case oldIndex
  then let res = (match stmt
  case s as STMT_ASSIGN(exp1=PATTERN(__)) then algStmtAssignPattern(s, context, &varDecls, &auxFunction)
  case s as STMT_ASSIGN(__)         then algStmtAssign(s, context, &varDecls, &auxFunction)
  case s as STMT_ASSIGN_ARR(__)     then algStmtAssignArr(s, context, &varDecls, &auxFunction)
  case s as STMT_TUPLE_ASSIGN(__)   then algStmtTupleAssign(s, context, &varDecls, &auxFunction)
  case s as STMT_IF(__)             then algStmtIf(s, context, &varDecls, &auxFunction)
  case s as STMT_FOR(__)            then algStmtFor(s, context, &varDecls, &auxFunction)
  case s as STMT_PARFOR(__)         then algStmtParForInterface(s, context, &varDecls, &auxFunction)
  case s as STMT_WHILE(__)          then algStmtWhile(s, context, &varDecls, &auxFunction)
  case s as STMT_ASSERT(__)         then algStmtAssert(s, context, &varDecls, &auxFunction)
  case s as STMT_TERMINATE(__)      then algStmtTerminate(s, context, &varDecls, &auxFunction)
  case s as STMT_WHEN(__)           then algStmtWhen(s, context, &varDecls, &auxFunction)
  case s as STMT_BREAK(__)          then 'break;<%\n%>'
  case s as STMT_CONTINUE(__)       then 'continue;<%\n%>'
  case s as STMT_FAILURE(__)        then algStmtFailure(s, context, &varDecls, &auxFunction)
  case s as STMT_RETURN(__)         then 'goto _return;<%\n%>'
  case s as STMT_NORETCALL(__)      then algStmtNoretcall(s, context, &varDecls, &auxFunction)
  case s as STMT_REINIT(__)         then algStmtReinit(s, context, &varDecls, &auxFunction)
  else error(sourceInfo(), 'ALG_STATEMENT NYI'))
  let () = System.tmpTickSetIndex(oldIndex,1)
  <<
  <%modelicaLine(getElementSourceFileInfo(getStatementSource(stmt)))%><%res%>
  <%endModelicaLine()%>
  >>
end algStatement;


template algStmtAssign(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an assigment algorithm statement."
::=
  match stmt
  case STMT_ASSIGN(exp=CALL(path=IDENT(name="fail"))) then
    '<%generateThrow()%><%\n%>'
  case STMT_ASSIGN(exp1=CREF(componentRef=WILD(__)), exp=e) then
    let &preExp = buffer ""
    let expPart = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    >>
  case STMT_ASSIGN(exp1=RSUB(exp=explhs as CREF(ty=t1 as T_METARECORD(__)), fieldName=fieldName))
  case STMT_ASSIGN(exp1=RSUB(exp=explhs as CREF(ty=t1 as T_METAUNIONTYPE(__)), fieldName=fieldName))
  case STMT_ASSIGN(exp1=explhs as CREF(componentRef=CREF_QUAL(identType=T_METATYPE(ty=t1 as T_METAUNIONTYPE(__)), componentRef=cr2 as CREF_IDENT(ident=fieldName)), ty=t2))
  case STMT_ASSIGN(exp1=explhs as CREF(componentRef=CREF_QUAL(identType=T_METATYPE(ty=t1 as T_METARECORD(__)), componentRef=cr2 as CREF_IDENT(ident=fieldName)),ty=t2)) then
    let &preExp = buffer ""
    let tmp = tempDecl("modelica_metatype",&varDecls)
    let varPart = daeExp(explhs, context, &preExp, &varDecls, &auxFunction)
    let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    let indexInRecord = intAdd(1, lookupIndexInMetaRecord(getMetaRecordFields(t1), fieldName))
    let len = intAdd(2, listLength(getMetaRecordFields(t1)))
    <<
    <%preExp%>
    <%tmp%> = MMC_TAGPTR(mmc_alloc_words(<%len%>));
    memcpy(MMC_UNTAGPTR(<%tmp%>), MMC_UNTAGPTR(<%varPart%>), <%len%>*sizeof(modelica_metatype));
    ((modelica_metatype*)MMC_UNTAGPTR(<%tmp%>))[<%indexInRecord%>] = <%expPart%>;
    <%varPart%> = <%tmp%>;
    >>

  case STMT_ASSIGN(exp1=RSUB(__)) then
    error(sourceInfo(), 'Code generation not implemented for lhs assignment <%printExpStr(exp1)%>')

  case STMT_ASSIGN(exp1=CREF(ty = T_FUNCTION_REFERENCE_VAR(__)))
  case STMT_ASSIGN(exp1=CREF(ty = T_FUNCTION_REFERENCE_FUNC(__))) then
    let &preExp = buffer ""
    let varPart = daeExpCrefLhs(exp1, context, &preExp, &varDecls, &auxFunction)
    let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    <%varPart%> = (modelica_fnptr) <%expPart%>;
    >>
    /* Records need to be traversed, assigning each component by itself */
  case STMT_ASSIGN(exp1=CREF(componentRef=cr,ty = ty as T_COMPLEX(varLst = varLst, complexClassType=RECORD(__)))) then
    let &preExp = buffer ""
    let rec = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl(expTypeModelica(ty),&varDecls)
    <<
    <%preExp%>
    <%tmp%> = <%rec%>;
    <% varLst |> var as TYPES_VAR(__) =>
      match var.ty
      case T_ARRAY(__) then
        copyArrayData(var.ty, '<%tmp%>._<%var.name%>', appendStringCref(var.name,cr), context, &preExp, &varDecls, &auxFunction)
      else
        let varPart = contextCref(appendStringCref(var.name,cr),context, &auxFunction)
        '<%varPart%> = <%tmp%>._<%var.name%>;'
    ; separator="\n"
    %>
    >>
  case STMT_ASSIGN(exp1=CALL(path=path,expLst=expLst,attr=CALL_ATTR(ty= T_COMPLEX(varLst = varLst, complexClassType=RECORD(__))))) then
    let &preExp = buffer ""
    let rec = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    <% varLst |> var as TYPES_VAR(__) hasindex i1 fromindex 1 =>
      let re = daeExp(listGet(expLst,i1), context, &preExp, &varDecls, &auxFunction)
      '<%re%> = <%rec%>._<%var.name%>;'
    ; separator="\n"
    %>
    >>
  case STMT_ASSIGN(exp1=CREF(__)) then
    let &preExp = buffer ""
    let varPart = daeExpCrefLhs(exp1, context, &preExp, &varDecls, &auxFunction)
    let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    <%varPart%> = <%expPart%>;
    >>
  case STMT_ASSIGN(exp1=exp1 as ASUB(__),exp=val) then
    (match expTypeFromExpShort(exp)
      case "metatype" then
        // MetaModelica Array
        (match exp1 case ASUB(exp=arr, sub={idx}) then
        let &preExp = buffer ""
        let arr1 = daeExp(arr, context, &preExp, &varDecls, &auxFunction)
        let idx1 = daeExp(idx, context, &preExp, &varDecls, &auxFunction)
        let val1 = daeExp(val, context, &preExp, &varDecls, &auxFunction)
        <<
        <%preExp%>
        arrayUpdate(<%arr1%>,<%idx1%>,<%val1%>);
        >>)
        // Modelica Array
      else
        let &preExp = buffer ""
        let varPart = daeExpAsub(exp1, context, &preExp, &varDecls, &auxFunction)
        let expPart = daeExp(val, context, &preExp, &varDecls, &auxFunction)
        <<
        <%preExp%>
        <%varPart%> = <%expPart%>;
        >>
    )
  case STMT_ASSIGN(__) then
    let &preExp = buffer ""
    let expPart1 = daeExp(exp1, context, &preExp, &varDecls, &auxFunction)
    let expPart2 = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    <%expPart1%> = <%expPart2%>;
    >>
end algStmtAssign;


template algStmtAssignArr(DAE.Statement stmt, Context context,
                 Text &varDecls, Text &auxFunction)
 "Generates an array assigment algorithm statement."
::=
match stmt
case STMT_ASSIGN_ARR(lhs=lhsexp as CREF(componentRef=cr), exp=RANGE(__), type_=t) then
  fillArrayFromRange(t,exp,cr,context,&varDecls,&auxFunction)

case STMT_ASSIGN_ARR(lhs=lhsexp as CREF(componentRef=cr), exp=e, type_=t) then
  let &preExp = buffer ""
  let expPart = daeExp(e, context, &preExp, &varDecls, &auxFunction)
  let assign = algStmtAssignArrWithRhsExpStr(lhsexp, expPart, context, &preExp, &varDecls, &auxFunction)
  <<
  <%preExp%>
  <%assign%>
  >>
end algStmtAssignArr;

template algStmtAssignWithRhsExpStr(DAE.Exp lhsexp, Text &rhsExpStr, Context context,
                 Text &preExp, Text &postExp, Text &varDecls, Text &auxFunction)
 "Generates an array assigment algorithm statement."
::=
match lhsexp
  case CREF(componentRef=WILD(__)) then
    '<%rhsExpStr%>;'
  case CREF(componentRef=cr, ty = T_ARRAY(ty=basety, dims=dims)) then
    algStmtAssignArrWithRhsExpStr(lhsexp, rhsExpStr, context, &preExp, &varDecls, &auxFunction)
  case CREF(componentRef = cr, ty=DAE.T_COMPLEX(complexClassType=RECORD(__))) then
    algStmtAssignRecordWithRhsExpStr(lhsexp, rhsExpStr, context, &preExp, &varDecls, &auxFunction)
  case CREF(__) then
    let lhsStr = daeExpCrefLhs(lhsexp, context, &preExp, &varDecls, &auxFunction)
    '<%lhsStr%> = <%rhsExpStr%>;'

  /*This CALL on left hand side case shouldn't have been created by the compiler. It only comes because of alias eliminations. On top of that
  at least it should have been a record_constructor not a normal call. sigh. */
  case CALL(path=path,expLst=expLst,attr=CALL_ATTR(ty=ty as T_COMPLEX(varLst = varLst, complexClassType=RECORD(__)))) then
    let tmp = tempDecl(expTypeModelica(ty),&varDecls)
    /*TODO handle array record memebers. see algStmtAssign*/
    <<
    <%preExp%>
    <%tmp%> = <%rhsExpStr%>;
    <% varLst |> var as TYPES_VAR(__) hasindex i1 fromindex 1 =>
      let re = daeExpCrefLhs(listGet(expLst,i1), context, &preExp, &varDecls, &auxFunction)
      '<%re%> = <%tmp%>._<%var.name%>;'
    ; separator="\n"
    %>
    >>
  else
    error(sourceInfo(), 'algStmtAssignWithRhsExpStr: Unhandled lhs expression. <%ExpressionDump.printExpStr(lhsexp)%>')
end algStmtAssignWithRhsExpStr;

template algStmtAssignRecordWithRhsExpStr(DAE.Exp lhsexp, Text &rhsExpStr, Context context,
                 Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates an array assigment algorithm statement."
::=
match lhsexp
  case CREF(componentRef = cr, ty=DAE.T_COMPLEX(varLst = varLst, complexClassType=RECORD(__))) then
    let lhsStr = contextCref(cr, context, &auxFunction)
    let tmp = tempDecl(expTypeModelica(ty),&varDecls)
    /*TODO handle array record memebers. see algStmtAssign*/
    <<
    <%preExp%>
    <%tmp%> = <%rhsExpStr%>;
    <% varLst |> var as TYPES_VAR(__) hasindex i1 fromindex 0 =>
      '<%lhsStr%><%match context case FUNCTION_CONTEXT(__) then "._" else "$P"%><%var.name%> = <%tmp%>._<%var.name%>;'
    ; separator="\n"
    %>
    >>
end algStmtAssignRecordWithRhsExpStr;

template algStmtAssignArrWithRhsExpStr(DAE.Exp lhsexp, Text &rhsExpStr, Context context,
                 Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates an array assigment algorithm statement."
::=
match lhsexp
  case CREF(componentRef=cr, ty = T_ARRAY(ty=basety, dims=dims)) then
    let type = expTypeArray(ty)
    if crefSubIsScalar(cr) then
      let lhsStr = daeExpCrefLhs(lhsexp, context, &preExp, &varDecls, &auxFunction)
      'copy_<%type%>_data(<%rhsExpStr%>, &<%lhsStr%>);'
    else
      indexedAssign(lhsexp, rhsExpStr, context, &preExp, &varDecls, &auxFunction)
end algStmtAssignArrWithRhsExpStr;

template fillArrayFromRange(DAE.Type ty, Exp exp, DAE.ComponentRef cr, Context context,
                            Text &varDecls, Text &auxFunction)
 "Generates an array assigment to RANGE expressions. (Fills an array from range expresion)"
::=
match exp
case RANGE(__) then
  let &preExp = buffer ""
  let cref = contextArrayCref(cr, context)
  let ty_str = expTypeArray(ty)
  let start_exp = daeExp(start, context, &preExp, &varDecls, &auxFunction)
  let stop_exp = daeExp(stop, context, &preExp, &varDecls, &auxFunction)
  let step_exp = match step case SOME(stepExp) then daeExp(stepExp, context, &preExp, &varDecls, &auxFunction) else "1"
  <<
  <%preExp%>
  fill_<%ty_str%>_from_range(&<%cref%>, <%start_exp%>, <%step_exp%>, <%stop_exp%>);<%\n%>
  >>

end fillArrayFromRange;

template indexedAssign(DAE.Exp lhs, String exp, Context context,
                                        Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match lhs
  case ecr as CREF(componentRef=cr, ty=T_ARRAY(ty=aty, dims=dims)) then
    let arrayType = expTypeArray(ty)
    let ispec = daeExpCrefIndexSpec(crefSubs(cr), context, &preExp, &varDecls, &auxFunction)
    match context
      case FUNCTION_CONTEXT(__) then
        let cref = contextArrayCref(cr, context)
        'indexed_assign_<%arrayType%>(<%exp%>, &<%cref%>, &<%ispec%>);'
      case PARALLEL_FUNCTION_CONTEXT(__) then
        let cref = contextArrayCref(cr, context)
        'indexed_assign_<%arrayType%>(<%exp%>, &<%cref%>, &<%ispec%>);'
      else
        let type = expTypeShort(aty)
        let wrapperArray = tempDecl(arrayType, &varDecls)
        let dimsLenStr = listLength(crefDims(cr))
        let dimsValuesStr = (crefDims(cr) |> dim => dimension(dim) ;separator=", ")
        let arrName = contextCref(crefStripSubs(cr), context,&auxFunction)
        <<
        <%type%>_array_create(&<%wrapperArray%>, (modelica_<%type%>*)&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>);<%\n%>
        indexed_assign_<%arrayType%>(<%exp%>, &<%wrapperArray%>, &<%ispec%>);
        >>
  else
    error(sourceInfo(), 'indexedAssign simulationContext failed')
end indexedAssign;

template copyArrayData(DAE.Type ty, String exp, DAE.ComponentRef cr, Context context,
                                        Text &preExp, Text &varDecls, Text &auxFunction)
::=
  let type = expTypeArray(ty)
  let cref = contextArrayCref(cr, context)
  match context
  case FUNCTION_CONTEXT(__) then
    'copy_<%type%><%if dimensionsKnown(ty) then "_data" /* else we make allocate and copy data */%>(<%exp%>, &<%cref%>);'
  case PARALLEL_FUNCTION_CONTEXT(__) then
    'copy_<%type%>_data(<%exp%>, &<%cref%>);'
  else
    'copy_<%type%>_data_mem(<%exp%>, &<%cref%>);'
end copyArrayData;

template algStmtTupleAssign(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a tuple assigment algorithm statement."
::=
match stmt
  case STMT_TUPLE_ASSIGN(expExpLst={_}) then
    error(sourceInfo(), "A tuple assignment of only one variable is a regular assignment")

  case STMT_TUPLE_ASSIGN(expExpLst = firstexp::_, exp = CALL(attr=CALL_ATTR(ty=T_TUPLE(types=ntys)))) then
    let &preExp = buffer ""
    let &postExp = buffer ""

    let lhsCrefs = (List.rest(expExpLst) |> e => " ," + tupleReturnVariableUpdates(e, context, varDecls, preExp, postExp, &auxFunction))
    // The tuple expressions might take fewer variables than the number of outputs. No worries.
    let lhsCrefs2 = lhsCrefs + List.fill(", NULL", intMax(0,intSub(listLength(ntys),listLength(expExpLst))))

    let call = daeExpCallTuple(exp, lhsCrefs2, context, &preExp, &varDecls, &auxFunction)
    let callassign = algStmtAssignWithRhsExpStr(firstexp, call, context, &preExp, &postExp, &varDecls, &auxFunction)
    <<
    /* tuple assignment <%expExpLst |> e => escapeCComments(printExpStr(e)) ; separator=", "%>*/
    <%preExp%>
    <%callassign%>
    <%postExp%>
    >>

  case STMT_TUPLE_ASSIGN(exp=MATCHEXPRESSION(__)) then
    let &preExp = buffer ""
    let prefix = 'tmp<%System.tmpTick()%>'
    // get the current index of tmpMeta and reserve N=listLength(inputs) values in it!
    let startIndexOutputs = '<%System.tmpTickIndexReserve(1, listLength(expExpLst))%>'
    let _ = daeExpMatch2(exp, expExpLst, prefix, startIndexOutputs, context, &preExp, &varDecls, &auxFunction)
    let lhsCrefs = (expExpLst |> crefexp as CREF(componentRef = cr) hasindex i0 fromindex 1 =>
                      let rhsStr = getTempDeclMatchOutputName(expExpLst, prefix, startIndexOutputs, i0)
                      let lhsStr = contextCref(cr, context, &auxFunction)
                      <<
                      <%lhsStr%> = <%rhsStr%>;
                      >>
                    ;separator="\n"; empty)
    <<
    <%expExpLst |> crefexp hasindex i0 =>
      let typ = expTypeFromExpModelica(crefexp)
      let decl = tempDeclMatchOutput(typ, prefix, startIndexOutputs, i0, &varDecls)
      ""
    ;separator="\n";empty%>
    <%preExp%>
    <%lhsCrefs%>
    >>
  else error(sourceInfo(), 'algStmtTupleAssign failed')

end algStmtTupleAssign;

template tupleReturnVariableUpdates(Exp inExp, Context context, Text &varDecls, Text &preExp, Text &varCopy, Text &auxFunction)
 "Generates code for updating variables  returned from fuctions that return tuples.
  Generates copies depending on what kind of variable is returned."
::=
  match inExp
  case CREF(componentRef=WILD(__)) then
    'NULL'
  case CREF(componentRef = cr, ty=DAE.T_COMPLEX(varLst = varLst, complexClassType=RECORD(__))) then
    let rhsStr = tempDecl(expTypeArrayIf(ty), &varDecls)
    let lhsStr = contextCref(cr, context, &auxFunction)
    let &varCopy +=
      /*TODO handle array record memebers. see algStmtAssign*/
      <<
      <%preExp%>
      <% varLst |> var as TYPES_VAR(__) hasindex i1 fromindex 0 =>
        '<%lhsStr%><%match context case FUNCTION_CONTEXT(__) then "._" else "$P"%><%var.name%> = <%rhsStr%>._<%var.name%>;'
      ; separator="\n"
      %>
      >> /*varCopy end*/
    '&<%rhsStr%>'

  /*This CALL case shouldn't have been created by the compiler. It only comes because of alias eliminations. On top of that
  at least it should have been a record_constractor not a normal call. sigh. */
  case CALL(path=path,expLst=expLst,attr=CALL_ATTR(ty=ty as T_COMPLEX(varLst = varLst, complexClassType=RECORD(__)))) then
    let &preExp = buffer ""
    let rhsStr = tempDecl(expTypeArrayIf(ty), &varDecls)
    let tmp = tempDecl(expTypeModelica(ty),&varDecls)
    let &varCopy +=
      /*TODO handle array record memebers. see algStmtAssign*/
      <<
      <%preExp%>
      <% varLst |> var as TYPES_VAR(__) hasindex i1 fromindex 1 =>
        let re = daeExp(listGet(expLst,i1), context, &preExp, &varDecls, &auxFunction)
        '<%re%> = <%rhsStr%>._<%var.name%>;'
      ; separator="\n"
      %>
      >> /*varCopy end*/
    '&<%rhsStr%>'
  case CREF(__) then
    let res = daeExpCrefLhs(inExp, context, &preExp, &varDecls, &auxFunction)
    if isArrayWithUnknownDimension(ty)
    then
      let &preExp += '<%res%>.dim_size = NULL;<%\n%>'
      '&<%res%>'
    else '&<%res%>'
  else
    error(sourceInfo(), 'tupleReturnVariableUpdates: Unhandled expression. <%ExpressionDump.printExpStr(inExp)%>')
end tupleReturnVariableUpdates;

template algStmtIf(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an if algorithm statement."
::=
match stmt
case STMT_IF(__) then
  let &preExp = buffer ""
  let condExp = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  <<
  <%preExp%>
  if(<%condExp%>)
  {
    <%statementLst |> stmt => algStatement(stmt, context, &varDecls, &auxFunction) ;separator="\n"%>
  }
  <%elseExpr(else_, context, &varDecls, &auxFunction)%>
  >>
end algStmtIf;

template algStmtParForBody(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement."
::=
  match stmt
  case s as STMT_PARFOR(range=rng as RANGE(__)) then
    algStmtParForRangeBody(s, context, &varDecls, &auxFunction)
  case s as STMT_PARFOR(__) then
    algStmtForGeneric(s, context, &varDecls, &auxFunction)
end algStmtParForBody;

template algStmtParForRangeBody(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement where range is RANGE."
::=
match stmt
case STMT_PARFOR(range=rng as RANGE(__)) then
  let iterName = contextIteratorName(iter, context)
  let identType = expType(type_, iterIsArray)
  let identTypeShort = expTypeShort(type_)

  let parforKernelName = 'parfor_<%System.tmpTickIndex(20 /* parfor */)%>'

  let &loopVarDecls = buffer ""
  let body = (statementLst |> stmt => algStatement(stmt, context, &loopVarDecls, &auxFunction)
                 ;separator="\n")

  // Reconstruct array arguments to structures in the kernels
  let &reconstrucedArrays = buffer ""
  let _ = (loopPrlVars |> var =>
      reconstructKernelArraysFromLooptupleVars(var, &reconstrucedArrays)
    )

  let argStr = (loopPrlVars |> var => '<%parFunArgDefinitionFromLooptupleVar(var)%>' ;separator=", \n")

  <<

  __kernel void <%parforKernelName%>(
        modelica_integer loop_start,
        modelica_integer loop_step,
        modelica_integer loop_end,
        <%argStr%>)
  {
    /* algStmtParForRangeBody : Thread managment for parfor loops */
    modelica_integer inner_start = (get_global_id(0) * loop_step) + (loop_start);
    modelica_integer stride = get_global_size(0) * loop_step;

    for(modelica_integer <%iterName%> = (modelica_integer) inner_start; in_range_integer(<%iterName%>, loop_start, loop_end); <%iterName%> += stride)
    {
      /* algStmtParForRangeBody : Reconstruct Arrays */
      <%reconstrucedArrays%>

      /* algStmtParForRangeBody : locals */
      <%loopVarDecls%>

      <%body%>
    }
  }
  >>
end algStmtParForRangeBody;

template algStmtParForInterface(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement."
::=
  match stmt
  case s as STMT_PARFOR(range=rng as RANGE(__)) then
    algStmtParForRangeInterface(s, context, &varDecls, &auxFunction)
  case s as STMT_PARFOR(__) then
    algStmtForGeneric(s, context, &varDecls, &auxFunction)
end algStmtParForInterface;

template algStmtParForRangeInterface(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement where range is RANGE."
::=
match stmt
case STMT_PARFOR(range=rng as RANGE(__)) then
  let identType = expType(type_, iterIsArray)
  let identTypeShort = expTypeShort(type_)
  let stmtStr = (statementLst |> stmt => algStatement(stmt, context, &varDecls, &auxFunction)
                 ;separator="\n")
  algStmtParForRangeInterface_impl(rng, iter, identType, identTypeShort, loopPrlVars, stmtStr, context, &varDecls, &auxFunction)
end algStmtParForRangeInterface;

template algStmtParForRangeInterface_impl(Exp range, Ident iterator, String type, String shortType, list<tuple<DAE.ComponentRef,builtin.SourceInfo>> loopPrlVars, Text body, Context context, Text &varDecls, Text &auxFunction)
 "The implementation of algStmtParForRangeInterface."
::=
match range
case RANGE(__) then
  let iterName = contextIteratorName(iterator, context)
  let startVar = tempDecl(type, &varDecls)
  let stepVar = tempDecl(type, &varDecls)
  let stopVar = tempDecl(type, &varDecls)
  let &preExp = buffer ""
  let startValue = daeExp(start, context, &preExp, &varDecls, &auxFunction)
  let stepValue = match step case SOME(eo) then
      daeExp(eo, context, &preExp, &varDecls, &auxFunction)
    else
      "(modelica_integer)1"
  let stopValue = daeExp(stop, context, &preExp, &varDecls, &auxFunction)

  let cl_kernelVar = tempDecl("cl_kernel", &varDecls)

  let parforKernelName = 'parfor_<%System.tmpTickIndex(20 /* parfor */)%>'

  let kerArgNr = '<%parforKernelName%>_arg_nr'

  let &kernelArgSets = buffer ""
  let _ = (loopPrlVars |> varTuple =>
      setKernelArgFormTupleLoopVars_ith(varTuple, &cl_kernelVar, &kerArgNr, &kernelArgSets, context)
    )

  <<
  <%preExp%>
  <%startVar%> = <%startValue%>; <%stepVar%> = <%stepValue%>; <%stopVar%> = <%stopValue%>;
  <%cl_kernelVar%> = ocl_create_kernel(omc_ocl_program, "<%parforKernelName%>");
  int <%kerArgNr%> = 0;

  ocl_set_kernel_arg(<%cl_kernelVar%>, <%kerArgNr%>, <%startVar%>); ++<%kerArgNr%>; <%\n%>
  ocl_set_kernel_arg(<%cl_kernelVar%>, <%kerArgNr%>, <%stepVar%>); ++<%kerArgNr%>; <%\n%>
  ocl_set_kernel_arg(<%cl_kernelVar%>, <%kerArgNr%>, <%stopVar%>); ++<%kerArgNr%>; <%\n%>

  <%kernelArgSets%>

  ocl_execute_kernel(<%cl_kernelVar%>);
  clReleaseKernel(<%cl_kernelVar%>);


  >> /* else we're looping over a zero-length range */
end algStmtParForRangeInterface_impl;


template algStmtFor(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement."
::=
  match stmt
  case s as STMT_FOR(range=rng as RANGE(__)) then
    algStmtForRange(s, context, &varDecls, &auxFunction)
  case s as STMT_FOR(__) then
    algStmtForGeneric(s, context, &varDecls, &auxFunction)
end algStmtFor;

template algStmtForRange(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement where range is RANGE."
::=
match stmt
case STMT_FOR(range=rng as RANGE(__)) then
  let identType = expType(type_, iterIsArray)
  let identTypeShort = expTypeShort(type_)
  let stmtStr = (statementLst |> stmt => algStatement(stmt, context, &varDecls, &auxFunction)
                 ;separator="\n")
  algStmtForRange_impl(rng, iter, identType, identTypeShort, stmtStr, context, &varDecls, &auxFunction)
end algStmtForRange;

template algStmtForRange_impl(Exp range, Ident iterator, String type, String shortType, Text body, Context context, Text &varDecls, Text &auxFunction)
 "The implementation of algStmtForRange, which is also used by daeExpReduction."
::=
match range
case RANGE(__) then
  let iterName = contextIteratorName(iterator, context)
  let startVar = tempDecl(type, &varDecls)
  let stepVar = tempDecl(type, &varDecls)
  let stopVar = tempDecl(type, &varDecls)
  let &preExp = buffer ""
  let startValue = daeExp(start, context, &preExp, &varDecls, &auxFunction)
  let stepValue = match step case SOME(eo) then
      daeExp(eo, context, &preExp, &varDecls, &auxFunction)
    else "1"
  let stopValue = daeExp(stop, context, &preExp, &varDecls, &auxFunction)
  let eqnsindx = match context case FUNCTION_CONTEXT(__) then '' else 'equationIndexes, '
  let AddionalFuncName = match context case FUNCTION_CONTEXT(__) then '' else '_withEquationIndexes'
  <<
  <%preExp%>
  <%startVar%> = <%startValue%>; <%stepVar%> = <%stepValue%>; <%stopVar%> = <%stopValue%>;
  if(!<%stepVar%>)
  {
    FILE_INFO info = omc_dummyFileInfo;
    omc_assert<%AddionalFuncName%>(threadData, info, <%eqnsindx%>"assertion range step != 0 failed");
  }
  else if(!(((<%stepVar%> > 0) && (<%startVar%> > <%stopVar%>)) || ((<%stepVar%> < 0) && (<%startVar%> < <%stopVar%>))))
  {
    <%type%> <%iterName%>;
    for(<%iterName%> = <%startValue%>; in_range_<%shortType%>(<%iterName%>, <%startVar%>, <%stopVar%>); <%iterName%> += <%stepVar%>)
    {
      <%body%>
    }
  }
  >> /* else we're looping over a zero-length range */
end algStmtForRange_impl;

template algStmtForGeneric(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a for algorithm statement where range is not RANGE."
::=
match stmt
case STMT_FOR(__) then
  let iterType = match expType(type_, iterIsArray)
    case "modelica_string" then "modelica_metatype"
    case s then s
  let arrayType = expTypeArray(type_)
  let tvar = match iterType
    case "modelica_metatype"
      then tempDecl("modelica_metatype", &varDecls)
    else   tempDecl("int", &varDecls)
  let stmtStr = (statementLst |> stmt =>
    algStatement(stmt, context, &varDecls, &auxFunction) ;separator="\n")
  algStmtForGeneric_impl(range, iter, iterType, arrayType, iterIsArray, stmtStr, tvar, context, &varDecls, &auxFunction)
end algStmtForGeneric;

template algStmtForGeneric_impl(Exp exp, Ident iterator, String type,
  String arrayType, Boolean iterIsArray, Text &body, Text tvar, Context context, Text &varDecls, Text &auxFunction)
 "The implementation of algStmtForGeneric, which is also used by daeExpReduction."
::=
  let iterName = contextIteratorName(iterator, context)
  let ivar = tempDecl(type, &varDecls)
  let &preExp = buffer ""
  let evar = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  <<
  <%preExp%>
  {
    <%type%> <%iterName%>;
    <% match type
    case "modelica_metatype" then
      (match typeof(exp)
      case T_METAARRAY(__)
      case T_METATYPE(ty=T_METAARRAY(__)) then
        let tmp = tempDecl("modelica_integer",&varDecls)
        let len = tempDecl("modelica_integer",&varDecls)
        <<
        for (<%tvar%> = <%evar%>, <%len%> = arrayLength(<%tvar%>), <%tmp%> = 1; <%tmp%> <= <%len%>; <%tmp%>++)
        {
          <%iterName%> = arrayGet(<%tvar%>,<%tmp%>);
          <%body%>
        }
        >>
      case T_METALIST(__)
      case T_METATYPE(ty=T_METALIST(__)) then
        <<
        for (<%tvar%> = <%evar%>; !listEmpty(<%tvar%>); <%tvar%>=listRest(<%tvar%>))
        {
          <%iterName%> = listHead(<%tvar%>);
          <%body%>
        }
        >>
      case ty then error(sourceInfo(), '<%unparseType(ty)%> iterator is not supported'))
    else
      let stmtStuff = if iterIsArray then
          'simple_index_alloc_<%type%>1(&<%evar%>, <%tvar%>, &<%ivar%>);'
        else
          '<%iterName%> = *(<%arrayType%>_element_addr1(&<%evar%>, 1, <%tvar%>));'
      <<
      for(<%tvar%> = 1; <%tvar%> <= size_of_dimension_base_array(<%evar%>, 1); ++<%tvar%>)
      {
        <%stmtStuff%>
        <%body%>
      }
      >>
    %>
  }
  >>
end algStmtForGeneric_impl;

template algStmtWhile(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a while algorithm statement."
::=
match stmt
case STMT_WHILE(__) then
  let &preExp = buffer ""
  let var = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  <<
  while(1)
  {
    <%preExp%>
    if(!<%var%>) break;
    <%statementLst |> stmt => algStatement(stmt, context, &varDecls, &auxFunction) ;separator="\n"%>
  }
  >>
end algStmtWhile;


template algStmtAssert(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an assert algorithm statement."
::=
match stmt
case STMT_ASSERT(source=SOURCE(info=info)) then
  assertCommon(cond, List.fill(msg,1), level, context, &varDecls, &auxFunction, info)
end algStmtAssert;

template algStmtTerminate(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an assert algorithm statement."
::=
match stmt
case STMT_TERMINATE(__) then
  let &preExp = buffer ""
  let msgVar = daeExp(msg, context, &preExp, &varDecls, &auxFunction)
  <<
  <%preExp%>
  FILE_INFO info = {<%infoArgs(getElementSourceFileInfo(source))%>};
  omc_terminate(info, MMC_STRINGDATA(<%msgVar%>));
  >>
end algStmtTerminate;

template algStmtFailure(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a failure() algorithm statement."
::=
match stmt
case STMT_FAILURE(__) then
  let tmp = tempDecl("modelica_boolean", &varDecls)
  let () = codegenPushTryThrowIndex(System.tmpTick())
  let goto = 'goto_<%codegenPeekTryThrowIndex()%>'
  let stmtBody = (body |> stmt =>
      algStatement(stmt, context, &varDecls, &auxFunction)
    ;separator="\n")
  <<
  <%tmp%> = 0; /* begin failure */
  MMC_TRY_INTERNAL(mmc_jumper)
    <%stmtBody%>
    <%tmp%> = 1;
  goto <%goto%>;
  <%goto%>:;
  MMC_CATCH_INTERNAL(mmc_jumper)<%let()=codegenPopTryThrowIndex() ""%>
  if (<%tmp%>) {<%generateThrow()%>;} /* end failure */
  >>
end algStmtFailure;

template algStmtNoretcall(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates a no return call algorithm statement."
::=
match stmt
case STMT_NORETCALL(exp=DAE.MATCHEXPRESSION(__)) then
  let &preExp = buffer ""
  let expPart = daeExpMatch2(exp,listExpLength1,"","",context,&preExp,&varDecls, &auxFunction)
  <<
  <%preExp%>
  <%expPart%>;
  >>
case STMT_NORETCALL(__) then
  let &preExp = buffer ""
  let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  <<
  <%preExp%>
  <% if isCIdentifier(expPart) then "" else '<%expPart%>;' %>
  >>
end algStmtNoretcall;

template algStmtWhen(DAE.Statement when, Context context, Text &varDecls, Text &auxFunction)
 "Generates a when algorithm statement."
::=
  match context
    case SIMULATION_CONTEXT(__) then
      match when
        case STMT_WHEN(__) then
          let helpIf = (conditions |> e => ' || (<%cref(e)%> && !$P$PRE<%cref(e)%> /* edge */)')
          let statements = (statementLst |> stmt =>
              algStatement(stmt, context, &varDecls, &auxFunction)
            ;separator="\n")
          let initial_statements = match initialCall
            case true then '<%statements%>'
            else '; /* nothing to do */'
          let else = algStatementWhenElse(elseWhen, &varDecls, &auxFunction)
          <<
          if(data->simulationInfo.discreteCall == 1)
          {
            if(initial())
            {
              <%initial_statements%>
            }
            else if(0<%helpIf%>)
            {
              <%statements%>
            }
            <%else%>
          }
          >>
      end match
  end match
end algStmtWhen;


template algStatementWhenElse(Option<DAE.Statement> stmt, Text &varDecls, Text &auxFunction)
 "Helper to algStmtWhen."
::=
match stmt
case SOME(when as STMT_WHEN(__)) then
  let statements = (when.statementLst |> stmt =>
      algStatement(stmt, contextSimulationDiscrete, &varDecls, &auxFunction)
    ;separator="\n")
  let else = algStatementWhenElse(when.elseWhen, &varDecls, &auxFunction)
  let elseCondStr = (when.conditions |> e => ' || (<%cref(e)%> && !$P$PRE<%cref(e)%> /* edge */)')
  <<
  else if(0<%elseCondStr%>)
  {
    <%statements%>
  }
  <%else%>
  >>
end algStatementWhenElse;

template algStmtReinit(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an assigment algorithm statement."
::=
  match stmt
  case STMT_REINIT(__) then
    let &preExp = buffer ""
    let expPart1 = daeExp(var, context, &preExp, &varDecls, &auxFunction)
    let expPart2 = daeExp(value, context, &preExp, &varDecls, &auxFunction)
    <<
    <%preExp%>
    <%expPart1%> = <%expPart2%>;
    infoStreamPrint(LOG_EVENTS, 0, "reinit <%expPart1%> = %f", <%expPart1%>);
    data->simulationInfo.needToIterate = 1;
    >>
end algStmtReinit;

template elseExpr(DAE.Else else_, Context context, Text &varDecls, Text &auxFunction)
 "Helper to algStmtIf."
 ::=
  match else_
  case NOELSE(__) then
    ""
  case ELSEIF(__) then
    let &preExp = buffer ""
    let condExp = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    <<
    else
    {
      <%preExp%>
      if(<%condExp%>)
      {
        <%statementLst |> stmt =>
          algStatement(stmt, context, &varDecls, &auxFunction)
        ;separator="\n"%>
      }
      <%elseExpr(else_, context, &varDecls, &auxFunction)%>
    }
    >>
  case ELSE(__) then

    <<
    else
    {
      <%statementLst |> stmt =>
        algStatement(stmt, context, &varDecls, &auxFunction)
      ;separator="\n"%>
    }
    >>
end elseExpr;

template functionsParModelicaKernelsFile(String filePrefix, Option<Function> mainFunction, list<Function> functions)
 "Generates the content of the C file for functions in the simulation case."
::=

  /* Reset the parfor loop id counter to 0*/
  let()= System.tmpTickResetIndex(0,20) /* parfor index */

  <<
  #include <ParModelica/explicit/openclrt/OCLRuntimeUtil.cl>

  // ParModelica Parallel Function headers.
  <%functionHeadersParModelica(filePrefix, functions)%>

  // Headers finish here.

  <%match mainFunction case SOME(fn) then functionBodyParModelica(fn,true)%>
  <%functionBodiesParModelica(functions)%>


  >>

end functionsParModelicaKernelsFile;

/* public */ template recordsFile(String filePrefix, list<RecordDeclaration> recordDecls)
 "Generates the content of the C file for functions in the simulation case.
  used in Compiler/Template/CodegenFMU.tpl"
::=
  <<
  /* Additional record code for <%filePrefix%> generated by the OpenModelica Compiler <%getVersionNr()%>. */

  #include "meta/meta_modelica.h"

  #ifdef __cplusplus
  extern "C" {
  #endif

  <%recordDecls |> rd => recordDeclaration(rd) ;separator="\n\n"%>

  #ifdef __cplusplus
  }
  #endif

  >>
  /* adpro: leave a newline at the end of file to get rid of warnings! */
end recordsFile;

template literalExpConst(Exp lit, Integer litindex, Text &preLit) "These should all be declared static X const"
::=
  let name = '_OMC_LIT<%litindex%>'
  let tmp = '_OMC_LIT_STRUCT<%litindex%>'
  let meta = 'static modelica_metatype const <%name%>'

  match lit
  case SCONST(__) then
    let escstr = Util.escapeModelicaStringToCString(string)
      /* TODO: Change this when OMC takes constant input arguments (so we cannot write to them)
               The cost of not doing this properly is small (<257 bytes of constants)
      match unescapedStringLength(escstr)
      case 0 then '#define <%name%> mmc_emptystring'
      case 1 then '#define <%name%> mmc_strings_len1["<%escstr%>"[0]]'
      else */
      <<
      #define <%name%>_data "<%escstr%>"
      static const MMC_DEFSTRINGLIT(<%tmp%>,<%unescapedStringLength(escstr)%>,<%name%>_data);
      #define <%name%> MMC_REFSTRINGLIT(<%tmp%>)
      >>
  case lit as MATRIX(ty=ty as T_ARRAY(__))
  case lit as ARRAY(ty=ty as T_ARRAY(__)) then
    let ndim = listLength(getDimensionSizes(ty))
    let sty = expTypeShort(ty)
    let dims = (getDimensionSizes(ty) |> dim => dim ;separator=", ")
    let data = flattenArrayExpToList(lit) |> exp => literalExpConstArrayVal(exp) ; separator=", "
    <<
    static _index_t <%name%>_dims[<%ndim%>] = {<%dims%>};
    <% match data case "" then
    <<
    static base_array_t const <%name%> = {
      <%ndim%>, <%name%>_dims, (void*) 0
    };
    >>
    else
    <<
    static const modelica_<%sty%> <%name%>_data[] = {<%data%>};
    static <%sty%>_array const <%name%> = {
      <%ndim%>, <%name%>_dims, (void*) <%name%>_data
    };
    >>
    %>
    >>
  case BOX(exp=exp as ICONST(__)) then
    <<
    <%meta%> = MMC_IMMEDIATE(MMC_TAGFIXNUM(<%exp.integer%>));
    >>
  case BOX(exp=exp as BCONST(__)) then
    <<
    <%meta%> = MMC_IMMEDIATE(MMC_TAGFIXNUM(<%boolStrC(exp.bool)%>));
    >>
  case BOX(exp=exp as RCONST(__)) then
    /* We need to use #define's to be C-compliant. Yea, total crap :) */
    <<
    static const MMC_DEFREALLIT(<%tmp%>,<%exp.real%>);
    #define <%name%> MMC_REFREALLIT(<%tmp%>)
    >>
  case CONS(__) then
    /* We need to use #define's to be C-compliant. Yea, total crap :) */
    <<
    static const MMC_DEFSTRUCTLIT(<%tmp%>,2,1) {<%literalExpConstBoxedVal(car,litindex + "_car", &preLit)%>,<%literalExpConstBoxedVal(cdr, litindex + "_cdr", &preLit)%>}};
    #define <%name%> MMC_REFSTRUCTLIT(<%tmp%>)
    >>
  case LIST(__) then
    let x = listReverse(valList) |> v hasindex i fromindex 1 =>
      /* We need to use #define's to be C-compliant. Yea, total crap :) */
      'static const MMC_DEFSTRUCTLIT(<%tmp + "_cons_" + i%>,2,1) {<%literalExpConstBoxedVal(v,tmp + "_elt_" + i, &preLit)%>,MMC_REFSTRUCTLIT(<% match i case 1 then "mmc_nil" else (tmp + "_cons_" + intSub(i,1))%>)}};<%\n%>'
    <<
    <%x%>
    #define <%name%> MMC_REFSTRUCTLIT(<%tmp%>_cons_<%listLength(valList)%>)
    >>
  case META_TUPLE(__) then
    /* We need to use #define's to be C-compliant. Yea, total crap :) */
    <<
    static const MMC_DEFSTRUCTLIT(<%tmp%>,<%listLength(listExp)%>,0) {<%listExp |> exp hasindex i0 => literalExpConstBoxedVal(exp,litindex+"_"+i0, &preLit); separator=","%>}};
    #define <%name%> MMC_REFSTRUCTLIT(<%tmp%>)
    >>
  case META_OPTION(exp=SOME(exp)) then
    /* We need to use #define's to be C-compliant. Yea, total crap :) */
    <<
    static const MMC_DEFSTRUCTLIT(<%tmp%>,1,1) {<%literalExpConstBoxedVal(exp,litindex+"_1", &preLit)%>}};
    #define <%name%> MMC_REFSTRUCTLIT(<%tmp%>)
    >>
  case METARECORDCALL(__) then
    /* We need to use #define's to be C-compliant. Yea, total crap :) */
    let newIndex = getValueCtor(index)
    <<
    static const MMC_DEFSTRUCTLIT(<%tmp%>,<%intAdd(1,listLength(args))%>,<%newIndex%>) {&<%underscorePath(path)%>__desc,<%args |> exp hasindex i0 => literalExpConstBoxedVal(exp,litindex+"_"+i0, &preLit); separator=","%>}};
    #define <%name%> MMC_REFSTRUCTLIT(<%tmp%>)
    >>
  else error(sourceInfo(), 'literalExpConst failed: <%printExpStr(lit)%>')
end literalExpConst;

template literalExpConstBoxedVal(Exp lit, Text index, Text &preLit)
::=
  let name = '_OMC_LIT<%index%>'
  let tmp = '_OMC_LIT_STRUCT<%index%>'
  match lit
  case ICONST(__) then 'MMC_IMMEDIATE(MMC_TAGFIXNUM(<%integer%>))'
  case ENUM_LITERAL(__) then 'MMC_IMMEDIATE(MMC_TAGFIXNUM(<%index%>))'
  case lit as BCONST(__) then 'MMC_IMMEDIATE(MMC_TAGFIXNUM(<%boolStrC(lit.bool)%>))'
  case lit as RCONST(__) then
    let &preLit +=
    <<
    static const MMC_DEFREALLIT(<%tmp%>,<%lit.real%>);
    #define <%name%> MMC_REFREALLIT(<%tmp%>)<%\n%>
    >>
    name
  case LIST(valList={}) then
    <<
    MMC_REFSTRUCTLIT(mmc_nil)
    >>
  case META_OPTION(exp=NONE()) then
    <<
    MMC_REFSTRUCTLIT(mmc_none)
    >>
  case lit as BOX(__) then literalExpConstBoxedVal(lit.exp, index, &preLit)
  case lit as SHARED_LITERAL(__) then '_OMC_LIT<%lit.index%>'
  else error(sourceInfo(), 'literalExpConstBoxedVal failed: <%printExpStr(lit)%>')
end literalExpConstBoxedVal;

template literalExpConstArrayVal(Exp lit)
::=
  match lit
    case ICONST(__) then integer
    case lit as BCONST(__) then boolStrC(lit.bool)
    case RCONST(__) then real
    case ENUM_LITERAL(__) then index
    case lit as SHARED_LITERAL(__) then '_OMC_LIT<%lit.index%>'
    else error(sourceInfo(), 'literalExpConstArrayVal failed: <%printExpStr(lit)%>')
end literalExpConstArrayVal;


template varType(Variable var)
 "Generates type for a variable."
::=
match var
case var as VARIABLE(parallelism = NON_PARALLEL()) then
  if instDims then
    expTypeArray(var.ty)
  else
    expTypeArrayIf(var.ty)
case var as VARIABLE(parallelism = PARGLOBAL()) then
  if instDims then
    'device_<%expTypeArray(var.ty)%>'
  else
    '<%expTypeArrayIf(var.ty)%>'
case var as VARIABLE(parallelism = PARLOCAL()) then
  if instDims then
    'device_local_<%expTypeArray(var.ty)%>'
  else
    expTypeArrayIf(var.ty)
end varType;

template varTypeBoxed(Variable var)
::=
match var
case VARIABLE(__) then 'modelica_metatype'
case FUNCTION_PTR(__) then 'modelica_fnptr'
end varTypeBoxed;



template expTypeRW(DAE.Type type)
 "Helper to writeOutVarRecordMembers."
::=
  match type
  case T_INTEGER(__)         then "TYPE_DESC_INT"
  case T_REAL(__)        then "TYPE_DESC_REAL"
  case T_STRING(__)      then "TYPE_DESC_STRING"
  case T_BOOL(__)        then "TYPE_DESC_BOOL"
  case T_ENUMERATION(__) then "TYPE_DESC_INT"
  case T_ARRAY(__)       then '<%expTypeRW(ty)%>_ARRAY'
  case T_COMPLEX(complexClassType=RECORD(__))
                      then "TYPE_DESC_RECORD"
  case T_METATYPE(__) case T_METABOXED(__)    then "TYPE_DESC_MMC"
end expTypeRW;

template expTypeShort(DAE.Type type)
 "Generate type helper."
::=
  match type
  case T_INTEGER(__)       then "integer"
  case T_REAL(__)          then "real"
  case T_STRING(__)        then "string"
  case T_BOOL(__)          then "boolean"
  case T_ENUMERATION(__)   then "integer"
  case T_SUBTYPE_BASIC(__) then expTypeShort(complexType)
  case T_ARRAY(__)         then expTypeShort(ty)
  case T_COMPLEX(complexClassType=EXTERNAL_OBJ(__)) then "complex"
  case T_COMPLEX(__)       then '<%underscorePath(ClassInf.getStateName(complexClassType))%>'
  case T_METAUNIONTYPE(__)
  case T_METAARRAY(__)
  case T_METALIST(__)
  case T_METATUPLE(__)
  case T_METAOPTION(__)
  case T_METAPOLYMORPHIC(__)
  case T_METATYPE(__)
  case T_METABOXED(__)     then "metatype"
  case T_FUNCTION(__)
  case T_FUNCTION_REFERENCE_FUNC(__)
  case T_FUNCTION_REFERENCE_VAR(__) then "fnptr"
  case T_UNKNOWN(__) then if acceptMetaModelicaGrammar() /* TODO: Don't do this to me! */
                          then "complex /* assumming void* for unknown type! when +g=MetaModelica */ "
                          else "real /* assumming real for uknown type! */"
  case T_ANYTYPE(__) then "complex" /* TODO: Don't do this to me! */
  else error(sourceInfo(),'expTypeShort: <%unparseType(type)%>')
end expTypeShort;

template mmcTypeShort(DAE.Type type)
::=
  match type
  case T_INTEGER(__)                 then "integer"
  case T_REAL(__)                    then "real"
  case T_STRING(__)                  then "string"
  case T_BOOL(__)                    then "integer"
  case T_ENUMERATION(__)             then "integer"
  case T_ARRAY(__)                   then "array"
  case T_METAUNIONTYPE(__)
  case T_METATYPE(__)
  case T_METALIST(__)
  case T_METAARRAY(__)
  case T_METAPOLYMORPHIC(__)
  case T_METAOPTION(__)
  case T_METATUPLE(__)
  case T_METABOXED(__)               then "metatype"
  case T_FUNCTION_REFERENCE_VAR(__)  then "fnptr"

  case T_COMPLEX(__)                 then "metatype"
  else error(sourceInfo(), 'mmcTypeShort:ERROR <%unparseType(type)%>')
end mmcTypeShort;


template expType(DAE.Type ty, Boolean array)
 "Generate type helper."
::=
  match array
  case true  then expTypeArray(ty)
  case false then expTypeModelica(ty)
end expType;


template expTypeModelica(DAE.Type ty)
 "Generate type helper."
::=
  expTypeFlag(ty, 2)
end expTypeModelica;


template expTypeArray(DAE.Type ty)
 "Generate type helper."
::=
  expTypeFlag(ty, 3)
end expTypeArray;


template expTypeArrayIf(DAE.Type ty)
 "Generate type helper."
::=
  expTypeFlag(ty, 4)
end expTypeArrayIf;


template expTypeFromExpShort(Exp exp)
 "Generate type helper."
::=
  expTypeFromExpFlag(exp, 1)
end expTypeFromExpShort;


template expTypeFromExpModelica(Exp exp)
 "Generate type helper."
::=
  expTypeFromExpFlag(exp, 2)
end expTypeFromExpModelica;


template expTypeFromExpArray(Exp exp)
 "Generate type helper."
::=
  expTypeFromExpFlag(exp, 3)
end expTypeFromExpArray;

template expTypeFromExpArrayIf(Exp exp)
 "Generate type helper."
::=
  expTypeFromExpFlag(exp, 4)
end expTypeFromExpArrayIf;

template expTypeFlag(DAE.Type ty, Integer flag)
 "Generate type helper."
::=
  match flag
  case 1 then
    // we want the short type
    expTypeShort(ty)
  case 2 then
    // we want the "modelica type"
    match ty case T_COMPLEX(complexClassType=EXTERNAL_OBJ(__)) then
      'modelica_<%expTypeShort(ty)%>'
    else match ty case T_COMPLEX(__) then
      '<%underscorePath(ClassInf.getStateName(complexClassType))%>'
    else match ty case T_ARRAY(ty = t as T_COMPLEX(__)) then
      expTypeShort(t)
    else
      'modelica_<%expTypeShort(ty)%>'
  case 3 then
    // we want the "array type"
    '<%expTypeShort(ty)%>_array'
  case 4 then
    // we want the "array type" only if type is array, otherwise "modelica type"
    (match ty
    case T_ARRAY(__) then '<%expTypeShort(ty)%>_array'
    else expTypeFlag(ty, 2))
  case 8 then
    (match ty
    case T_ARRAY(__) then '<%expTypeFlag(ty,8)%>*'
    case T_INTEGER(__) then 'int'
    case T_BOOL(__) then 'int'
    case T_REAL(__) then 'double'
    case T_STRING(__) then 'const char*'
    case T_SUBTYPE_BASIC(__) then '<%expTypeFlag(complexType,8)%>*'
    else error(sourceInfo(),'I do not know the external type of <%unparseType(ty)%>'))
end expTypeFlag;

template expTypeFromExpFlag(Exp exp, Integer flag)
 "Generate type helper."
::=
  match exp
  case ICONST(__)        then match flag case 8 then "int" case 1 then "integer" else "modelica_integer"
  case RCONST(__)        then match flag case 1 then "real" else "modelica_real"
  case SCONST(__)        then match flag case 1 then "string" else "modelica_string"
  case BCONST(__)        then match flag case 1 then "boolean" else "modelica_boolean"
  case ENUM_LITERAL(__)  then match flag case 8 then "int" case 1 then "integer" else "modelica_integer"
  case e as BINARY(__)
  case e as UNARY(__)
  case e as LBINARY(__)
  case e as LUNARY(__)   then expTypeFromOpFlag(e.operator, flag)
  case e as RELATION(__) then match flag case 1 then "boolean" else "modelica_boolean"
  case IFEXP(__)         then expTypeFromExpFlag(expThen, flag)
  case CALL(attr=CALL_ATTR(__)) then expTypeFlag(attr.ty, flag)
  case c as RECORD(__) then expTypeFlag(c.ty, flag)
  case c as ARRAY(__)
  case c as MATRIX(__)
  case c as RANGE(__)
  case c as CAST(__)
  case c as TSUB(__)
  case c as CREF(__)
  case c as CODE(__)     then expTypeFlag(c.ty, flag)
  case c as ASUB(__)     then expTypeFlag(typeof(c), flag)
  case REDUCTION(__)     then expTypeFlag(typeof(exp), flag)
  case CONS(__)
  case LIST(__)
  case SIZE(__)          then expTypeFlag(typeof(exp), flag)

  case META_TUPLE(__)
  case META_OPTION(__)
  case MATCHEXPRESSION(__)
  case METARECORDCALL(__)
  case RSUB(__)
  case BOX(__)           then match flag case 1 then "metatype" else "modelica_metatype"
  case c as UNBOX(__)    then expTypeFlag(c.ty, flag)
  case c as SHARED_LITERAL(__) then expTypeFromExpFlag(c.exp, flag)
  else error(sourceInfo(), 'expTypeFromExpFlag(flag=<%flag%>):<%printExpStr(exp)%>')
end expTypeFromExpFlag;


template expTypeFromOpFlag(Operator op, Integer flag)
 "Generate type helper."
::=
  match op
  case o as ADD(__)
  case o as SUB(__)
  case o as MUL(__)
  case o as DIV(__)
  case o as POW(__)

  case o as UMINUS(__)
  case o as UMINUS_ARR(__)
  case o as ADD_ARR(__)
  case o as SUB_ARR(__)
  case o as MUL_ARR(__)
  case o as DIV_ARR(__)
  case o as MUL_ARRAY_SCALAR(__)
  case o as ADD_ARRAY_SCALAR(__)
  case o as SUB_SCALAR_ARRAY(__)
  case o as MUL_SCALAR_PRODUCT(__)
  case o as MUL_MATRIX_PRODUCT(__)
  case o as DIV_ARRAY_SCALAR(__)
  case o as DIV_SCALAR_ARRAY(__)
  case o as POW_ARRAY_SCALAR(__)
  case o as POW_SCALAR_ARRAY(__)
  case o as POW_ARR(__)
  case o as POW_ARR2(__)
  case o as LESS(__)
  case o as LESSEQ(__)
  case o as GREATER(__)
  case o as GREATEREQ(__)
  case o as EQUAL(__)
  case o as NEQUAL(__) then
    expTypeFlag(o.ty, flag)
  case o as AND(__)
  case o as OR(__)
  case o as NOT(__) then
    match flag case 1 then "boolean" else "modelica_boolean"
  else error(sourceInfo(), 'expTypeFromOpFlag:ERROR')
end expTypeFromOpFlag;

template dimension(Dimension d)
::=
  match d
  case DAE.DIM_BOOLEAN(__) then '2'
  case DAE.DIM_ENUM(__) then size
  case DAE.DIM_EXP(exp=e) then dimensionExp(e)
  case DAE.DIM_INTEGER(__) then
    if intEq(integer, -1) then
      error(sourceInfo(),"Negeative dimension(unknown dimensions) may not be part of generated code. This is most likely an error on the part of OpenModelica. Please submit a detailed bug-report.")
    else
      integer
  case DAE.DIM_UNKNOWN(__) then error(sourceInfo(),"Unknown dimensions may not be part of generated code. This is most likely an error on the part of OpenModelica. Please submit a detailed bug-report.")
  else error(sourceInfo(), 'dimension: INVALID_DIMENSION')
end dimension;

template dimensionExp(DAE.Exp dimExp)
::=
  match dimExp
  case DAE.CREF(componentRef = cr) then cref(cr)
  else error(sourceInfo(), 'dimensionExp: INVALID_DIMENSION <%printExpStr(dimExp)%>')
end dimensionExp;

template algStmtAssignPattern(DAE.Statement stmt, Context context, Text &varDecls, Text &auxFunction)
 "Generates an assigment algorithm statement."
::=
  match stmt
  case s as STMT_ASSIGN(exp1=lhs as PATTERN(pattern=PAT_CALL_TUPLE(patterns=pat::patterns)),exp=CALL(attr=CALL_ATTR(ty=T_TUPLE(types=ty::tys)))) then
    let &preExp = buffer ""
    let &assignments1 = buffer ""
    let &assignments = buffer ""
    let &additionalOutputs = buffer ""
    let &matchPhase = buffer ""
    let _ = threadTuple(patterns,tys) |> (pat,ty) => match pat
      case PAT_WILD(__) then
        let &additionalOutputs += ", NULL"
        ""
      else
        let v = tempDecl(expTypeArrayIf(ty), &varDecls)
        let &additionalOutputs += ', &<%v%>'
        let &matchPhase += patternMatch(pat,v,generateThrow(),&varDecls,&assignments)
        ""
    let expPart = daeExpCallTuple(s.exp,additionalOutputs,context, &preExp, &varDecls, &auxFunction)
    match pat
      case PAT_WILD(__) then '/* Pattern-matching tuple assignment, wild first pattern */<%\n%><%preExp%><%expPart%>;<%\n%><%matchPhase%><%assignments%>'
      else
        let v = tempDecl(expTypeArrayIf(ty), &varDecls)
        let res = patternMatch(pat,v,generateThrow(),&varDecls,&assignments1)
        <<
        /* Pattern-matching tuple assignment */
        <%preExp%>
        <%v%> = <%expPart%>;
        <%res%><%assignments1%><%matchPhase%><%assignments%>
        >>
  case s as STMT_ASSIGN(exp1=lhs as PATTERN(pattern=PAT_WILD(__))) then
    error(sourceInfo(),'Improve simplifcation, got pattern assignment _ = <%printExpStr(exp)%>, expected NORETCALL')
  case s as STMT_ASSIGN(exp1=lhs as PATTERN(__)) then
    let &preExp = buffer ""
    let &assignments = buffer ""
    let expPart = daeExp(s.exp, context, &preExp, &varDecls, &auxFunction)
    let v = tempDecl(expTypeFromExpModelica(s.exp), &varDecls)
    <<
    /* Pattern-matching assignment */
    <%preExp%>
    <%v%> = <%expPart%>;
    <%patternMatch(lhs.pattern,v,generateThrow(),&varDecls,&assignments)%><%assignments%>
    >>
end algStmtAssignPattern;

template patternMatch(Pattern pat, Text rhs, Text onPatternFail, Text &varDecls, Text &assignments)
::=
  match pat
  case PAT_WILD(__) then ""
  case p as PAT_CONSTANT(__)
    then
      let &unboxBuf = buffer ""
      let urhs = (match p.ty
        case SOME(et) then unboxVariable(rhs, et, &unboxBuf, &varDecls)
        else rhs
      )
      <<<%unboxBuf%><%match p.exp
        case c as ICONST(__) then 'if (<%c.integer%> != <%urhs%>) <%onPatternFail%>;<%\n%>'
        case c as RCONST(__) then 'if (<%c.real%> != <%urhs%>) <%onPatternFail%>;<%\n%>'
        case c as SCONST(__) then
          let escstr = Util.escapeModelicaStringToCString(c.string)
          'if (<%unescapedStringLength(escstr)%> != MMC_STRLEN(<%urhs%>) || strcmp("<%escstr%>", MMC_STRINGDATA(<%urhs%>)) != 0) <%onPatternFail%>;<%\n%>'
        case c as BCONST(__) then 'if (<%boolStrC(c.bool)%> != <%urhs%>) <%onPatternFail%>;<%\n%>'
        case c as LIST(valList = {}) then 'if (!listEmpty(<%urhs%>)) <%onPatternFail%>;<%\n%>'
        case c as META_OPTION(exp = NONE()) then 'if (!optionNone(<%urhs%>)) <%onPatternFail%>;<%\n%>'
        case c as ENUM_LITERAL() then 'if (<%c.index%> != <%urhs%>) <%onPatternFail%>;<%\n%>'
        else error(sourceInfo(), 'UNKNOWN_CONSTANT_PATTERN <%printExpStr(p.exp)%>')
      %>>>
  case p as PAT_SOME(__) then
    let tvar = tempDecl("modelica_metatype", &varDecls)
    <<if (optionNone(<%rhs%>)) <%onPatternFail%>;
    <%tvar%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%rhs%>), 1));
    <%patternMatch(p.pat,tvar,onPatternFail,&varDecls,&assignments)%>>>
  case PAT_CONS(__) then
    let tvarHead = tempDecl("modelica_metatype", &varDecls)
    let tvarTail = tempDecl("modelica_metatype", &varDecls)
    <<if (listEmpty(<%rhs%>)) <%onPatternFail%>;
    <%tvarHead%> = MMC_CAR(<%rhs%>);
    <%tvarTail%> = MMC_CDR(<%rhs%>);
    <%patternMatch(head,tvarHead,onPatternFail,&varDecls,&assignments)%><%patternMatch(tail,tvarTail,onPatternFail,&varDecls,&assignments)%>>>
  case PAT_META_TUPLE(__)
    then
      (patterns |> p hasindex i1 fromindex 1 =>
        match p
        case PAT_WILD(__) then ""
        else
        let tvar = tempDecl("modelica_metatype", &varDecls)
        <<<%tvar%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%rhs%>), <%i1%>));
        <%patternMatch(p,tvar,onPatternFail,&varDecls,&assignments)%>
        >>; empty /* increase the counter even if no output is produced */)
  case PAT_CALL_TUPLE(__)
    then
      // misnomer. Call expressions no longer return tuples using these structs. match-expressions and if-expressions converted to Modelica tuples do
      (patterns |> p hasindex i1 fromindex 1 =>
        match p
        case PAT_WILD(__) then ""
        else
        let nrhs = '<%rhs%>.c<%i1%>'
        patternMatch(p,nrhs,onPatternFail,&varDecls,&assignments)
        ; empty /* increase the counter even if no output is produced */
      )
  case PAT_CALL_NAMED(__)
    then
      <<<%patterns |> (p,n,t) =>
        match p
        case PAT_WILD(__) then ""
        else
        let tvar = tempDecl(expTypeArrayIf(t), &varDecls)
        <<<%tvar%> = <%rhs%>._<%n%>;
        <%patternMatch(p,tvar,onPatternFail,&varDecls,&assignments)%>
        >>%>
      >>
  case PAT_CALL(__)
    then
      <<<%if not knownSingleton then 'if (mmc__uniontype__metarecord__typedef__equal(<%rhs%>,<%index%>,<%listLength(patterns)%>) == 0) <%onPatternFail%>;<%\n%>'%><%
      (patterns |> p hasindex i2 fromindex 2 =>
        match p
        case PAT_WILD(__) then ""
        else
        let tvar = tempDecl("modelica_metatype", &varDecls)
        <<<%tvar%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%rhs%>), <%i2%>));
        <%patternMatch(p,tvar,onPatternFail,&varDecls,&assignments)%>
        >> ;empty) /* increase the counter even if no output is produced */
      %>
      >>
  case p as PAT_AS_FUNC_PTR(__) then
    let &assignments += '_<%p.id%> = <%rhs%>;<%\n%>'
    <<<%patternMatch(p.pat,rhs,onPatternFail,&varDecls,&assignments)%>
    >>
  case p as PAT_AS(ty = NONE()) then
    let &assignments += '_<%p.id%> = <%rhs%>;<%\n%>'
    <<<%patternMatch(p.pat,rhs,onPatternFail,&varDecls,&assignments)%>
    >>
  case p as PAT_AS(ty = SOME(et)) then
    let &unboxBuf = buffer ""
    let &assignments += '_<%p.id%> = <%unboxVariable(rhs, et, &unboxBuf, &varDecls)%>  /* pattern as ty=<%unparseType(et)%> */;<%\n%>'
    <<<%&unboxBuf%>
    <%patternMatch(p.pat,rhs,onPatternFail,&varDecls,&assignments)%>
    >>
  else error(sourceInfo(), 'UNKNOWN_PATTERN /* rhs: <%rhs%> */<%\n%>')
end patternMatch;

template infoArgs(SourceInfo info)
::=
  match info
  case SOURCEINFO(__) then '"<%Util.escapeModelicaStringToCString(testsuiteFriendly(fileName))%>",<%lineNumberStart%>,<%columnNumberStart%>,<%lineNumberEnd%>,<%columnNumberEnd%>,<%if isReadOnly then 1 else 0%>'
end infoArgs;

template assertCommon(Exp condition, list<Exp> messages, Exp level, Context context, Text &varDecls, Text &auxFunction, builtin.SourceInfo info)
::=
  let &preExpCond = buffer ""
  let condVar = daeExp(condition, context, &preExpCond, &varDecls, &auxFunction)
  let &preExpMsg = buffer ""
  let msgVar = messages |> message => expToFormatString(message,context,&preExpMsg,&varDecls,&auxFunction) ; separator = ", "
  let eqnsindx = match context case FUNCTION_CONTEXT(__) then '' else 'equationIndexes, '
  let AddionalFuncName = match context case FUNCTION_CONTEXT(__) then '' else '_withEquationIndexes'
  let addInfoTextContext = match context case FUNCTION_CONTEXT(__) then '' else '<%\n%>omc_assert_warning(info, "The following assertion has been violated at time %f\n<%Util.escapeModelicaStringToCString(printExpStr(condition))%>", time);'
  let omcAssertFunc = match level case ENUM_LITERAL(index=2) then 'omc_assert_warning<%AddionalFuncName%>(' else 'omc_assert<%AddionalFuncName%>(threadData, '
  let warningTriggered = tempDeclZero("static int", &varDecls)
  let TriggerIf = match level case ENUM_LITERAL(index=2) then 'if(!<%warningTriggered%>)<%\n%>' else ''
  let TriggerVarSet = match level case ENUM_LITERAL(index=2) then '<%warningTriggered%> = 1;<%\n%>' else ''
  <<
  <%TriggerIf%>
  {
    <%preExpCond%>
    if(!<%condVar%>)
    {
      <%preExpMsg%>
      FILE_INFO info = {<%infoArgs(info)%>};<%addInfoTextContext%>
      <%omcAssertFunc%>info, <%eqnsindx%><%msgVar%>);
      <%TriggerVarSet%>
    }
  }<%\n%>
  >>
end assertCommon;

template expToFormatString(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  'MMC_STRINGDATA(<%daeExp(exp, context, &preExp, &varDecls, &auxFunction)%>)'
end expToFormatString;

template assertCommonVar(Text condVar, Text msgVar, Context context, Text &preExpMsg, Text &varDecls, builtin.SourceInfo info)
::=
  match context
  case FUNCTION_CONTEXT(__) then
    <<
    if(!<%condVar%>)
    {
        <%preExpMsg%>
        FILE_INFO info = {<%infoArgs(info)%>};
        omc_assert(threadData, info, <%msgVar%>);
    }<%\n%>
    >>
  else
    <<
    if(!<%condVar%>)
    {
        <%preExpMsg%>
        FILE_INFO info = {<%infoArgs(info)%>};
        omc_assert_warning(info, "The following assertion has been violated at time %f", time);
        throwStreamPrintWithEquationIndexes(threadData, equationIndexes, <%msgVar%>);
    }<%\n%>
    >>
end assertCommonVar;

template contextCref(ComponentRef cr, Context context, Text &auxFunction)
  "Generates code for a component reference depending on which context we're in."
::=
  match context
  case FUNCTION_CONTEXT(__)
  case PARALLEL_FUNCTION_CONTEXT(__) then
    (match cr
    case CREF_QUAL(identType = T_ARRAY(ty = T_COMPLEX(complexClassType = record_state))) then
      let &preExp = buffer ""
      let &varDecls = buffer ""
      let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
      let recPtr = tempDecl(rec_name + "*", &varDecls)
      let dimsLenStr = listLength(crefSubs(cr))
      let dimsValuesStr = (crefSubs(cr) |> INDEX(__) => daeDimensionExp(exp, context, &preExp, &varDecls, &auxFunction) ; separator=", ")
      <<
      ((<%rec_name%>*)(generic_array_element_addr(&_<%ident%>, sizeof(<%rec_name%>), <%dimsLenStr%>, <%dimsValuesStr%>)))-><%contextCref(componentRef, context, &auxFunction)%>
      >>
    else "_" + System.unquoteIdentifier(crefStr(cr))
    )
  else cref(cr)
end contextCref;

template contextIteratorName(Ident name, Context context)
  "Generates code for an iterator variable."
::=
  match context
  case FUNCTION_CONTEXT(__) then "_" + name
  case PARALLEL_FUNCTION_CONTEXT(__) then "_" + name
  else "$P" + name
end contextIteratorName;

/* public */ template cref(ComponentRef cr)
 "Generates C equivalent name for component reference.
  used in Compiler/Template/CodegenFMU.tpl"
::=
  match cr
  case CREF_IDENT(ident = "xloc") then crefStr(cr)
  case CREF_IDENT(ident = "time") then "time"
  case WILD(__) then ''
  else "$P" + crefToCStr(cr)
end cref;

template crefToCStr(ComponentRef cr)
 "Helper function to cref."
::=
  match cr
  case CREF_IDENT(__) then '<%unquoteIdentifier(ident)%><%subscriptsToCStr(subscriptLst)%>'
  case CREF_QUAL(__) then '<%unquoteIdentifier(ident)%><%subscriptsToCStr(subscriptLst)%>$P<%crefToCStr(componentRef)%>'
  case WILD(__) then ''
  else "CREF_NOT_IDENT_OR_QUAL"
end crefToCStr;

template subscriptsToCStr(list<Subscript> subscripts)
::=
  if subscripts then
    '$lB<%subscripts |> s => subscriptToCStr(s) ;separator="$c"%>$rB'
end subscriptsToCStr;

template subscriptToCStr(Subscript subscript)
::=
  match subscript
  case SLICE(exp=ICONST(integer=i)) then i
  case SLICE(__) then error(sourceInfo(), "Unknown slice " + printExpStr(exp))
  case WHOLEDIM(__) then "WHOLEDIM"
  case INDEX(__) then
   match exp
    case ICONST(integer=i) then i
    case ENUM_LITERAL(index=i) then i
    case _ then
    let &varDecls = buffer ""
    let &preExp = buffer ""
    let &auxFunction = buffer ""
    let index = daeExp(exp, contextOther, &preExp, &varDecls, &auxFunction)
    '<%index%>'
   end match
  else error(sourceInfo(), "UNKNOWN_SUBSCRIPT")
end subscriptToCStr;

template contextArrayCref(ComponentRef cr, Context context)
 "Generates code for an array component reference depending on the context."
::=
  match context
  case FUNCTION_CONTEXT(__) then "_" + arrayCrefStr(cr)
  case PARALLEL_FUNCTION_CONTEXT(__) then "_" + arrayCrefStr(cr)
  else arrayCrefCStr(cr)
end contextArrayCref;

template arrayCrefCStr(ComponentRef cr)
::= '$P<%arrayCrefCStr2(cr)%>'
end arrayCrefCStr;

template arrayCrefCStr2(ComponentRef cr)
::=
  match cr
  case CREF_IDENT(__) then '<%unquoteIdentifier(ident)%>'
  case CREF_QUAL(__) then '<%unquoteIdentifier(ident)%><%subscriptsToCStr(subscriptLst)%>$P<%arrayCrefCStr2(componentRef)%>'
  else "CREF_NOT_IDENT_OR_QUAL"
end arrayCrefCStr2;

template arrayCrefStr(ComponentRef cr)
::=
  match cr
  case CREF_IDENT(__) then '<%ident%>'
  case CREF_QUAL(__) then '<%ident%>._<%arrayCrefStr(componentRef)%>'
  else "CREF_NOT_IDENT_OR_QUAL"
end arrayCrefStr;

template crefFunctionName(ComponentRef cr)
::=
  match cr
  case CREF_IDENT(__) then
    System.stringReplace(unquoteIdentifier(ident), "_", "__")
  case CREF_QUAL(__) then
    '<%System.stringReplace(unquoteIdentifier(ident), "_", "__")%>_<%crefFunctionName(componentRef)%>'
end crefFunctionName;

template addRootsTempArray()
::=
  match System.tmpTickMaximum(1)
    case 0 then ""
    case i then /* TODO: Find out where we add tmpIndex but discard its use causing us to generate unused tmpMeta with size 1 */
      <<
      modelica_metatype tmpMeta[<%i%>] __attribute__((unused)) = {0};
      >>
end addRootsTempArray;

template modelicaLine(builtin.SourceInfo info)
::=
  if boolOr(acceptMetaModelicaGrammar(), Flags.isSet(Flags.GEN_DEBUG_SYMBOLS)) then '/*#modelicaLine <%infoStr(info)%>*/<%\n%>'
end modelicaLine;

template endModelicaLine()
::=
  if boolOr(acceptMetaModelicaGrammar(), Flags.isSet(Flags.GEN_DEBUG_SYMBOLS)) then '/*#endModelicaLine*/<%\n%>'
end endModelicaLine;

template tempDecl(String ty, Text &varDecls)
 "Declares a temporary variable in varDecls and returns the name."
::=
  let newVar =
    match ty /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%System.tmpTickIndex(1)%>]'
      else
        let newVarIx = 'tmp<%System.tmpTick()%>'
        let &varDecls += '<%ty%> <%newVarIx%>;<%\n%>'
        newVarIx
  newVar
end tempDecl;

template tempDeclZero(String ty, Text &varDecls)
 "Declares a temporary variable initialized to zero in varDecls and returns the name."
::=
  let newVar
         =
    match ty /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%System.tmpTickIndex(1)%>]'
      else
        let newVarIx = 'tmp<%System.tmpTick()%>'
        let &varDecls += '<%ty%> <%newVarIx%> = 0;<%\n%>'
        newVarIx
  newVar
end tempDeclZero;

template tempDeclMatchInput(String ty, String prefix, String startIndex, String index, Text &varDecls)
 "Declares a temporary variable in varDecls for variables in match input list and returns the name."
::=
  let newVar
         =
    match ty /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%startIndex%>+<%index%>]'
      else
        let newVarIx = '<%prefix%>_in<%index%>'
        let &varDecls += '<%ty%> <%newVarIx%>;<%\n%>'
        newVarIx
  newVar
end tempDeclMatchInput;

template getTempDeclMatchInputName(list<Exp> inputs, String prefix, String startIndex, Integer index)
 "Returns the name of the temporary variable from the match input list."
::=
  let typ = '<%expTypeFromExpModelica(listGet(inputs, index))%>'
  let newVar =
      match typ /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%startIndex%>+<%intSub(index, 1)%>]'
      else
        let newVarIx = '<%prefix%>_in<%intSub(index, 1)%>'
        newVarIx
  newVar
end getTempDeclMatchInputName;

template tempDeclMatchOutput(String ty, String prefix, String startIndex, String index, Text &varDecls)
 "Declares a temporary variable in varDecls for variables in match output list and returns the name."
::=
  let newVar
         =
    match ty /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%startIndex%>+<%index%>]'
      else
        let newVarIx = '<%prefix%>_c<%index%>'
        let &varDecls += '<%ty%> <%newVarIx%> __attribute__((unused)) = 0;<%\n%>'
        newVarIx
  newVar
end tempDeclMatchOutput;

template getTempDeclMatchOutputName(list<Exp> outputs, String prefix, String startIndex, Integer index)
 "Returns the name of the temporary variable from the match input list."
::=
  let typ = '<%expTypeFromExpModelica(listGet(outputs, index))%>'
  let newVar =
      match typ /* TODO! FIXME! UGLY! UGLY! hack! */
      case "modelica_metatype"
      case "metamodelica_string"
      case "metamodelica_string_const"
        then 'tmpMeta[<%startIndex%>+<%intSub(index, 1)%>]'
      else
        let newVarIx = '<%prefix%>_c<%intSub(index, 1)%>'
        newVarIx
  newVar
end getTempDeclMatchOutputName;

/* public */ template daeExp(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for an expression.
  used in Compiler/Template/CodegenQSS.tpl"
::=
  match exp
  case e as ICONST(__)          then '(modelica_integer) <%integer%>' /* Yes, we need to cast int to long on 64-bit arch... */
  case e as RCONST(__)          then real
  case e as SCONST(__)          then daeExpSconst(string, &preExp, &varDecls)
  case e as BCONST(__)          then boolStrC(bool)
  case e as ENUM_LITERAL(__)    then index
  case e as CREF(__)            then daeExpCrefRhs(e, context, &preExp, &varDecls, &auxFunction)
  case e as BINARY(__)          then daeExpBinary(e, context, &preExp, &varDecls, &auxFunction)
  case e as UNARY(__)           then daeExpUnary(e, context, &preExp, &varDecls, &auxFunction)
  case e as LBINARY(__)         then daeExpLbinary(e, context, &preExp, &varDecls, &auxFunction)
  case e as LUNARY(__)          then daeExpLunary(e, context, &preExp, &varDecls, &auxFunction)
  case e as RELATION(__)        then daeExpRelation(e, context, &preExp, &varDecls, &auxFunction)
  case e as IFEXP(__)           then daeExpIf(e, context, &preExp, &varDecls, &auxFunction)
  case e as CALL(__)            then daeExpCall(e, context, &preExp, &varDecls, &auxFunction)
  case e as RECORD(__)          then daeExpRecord(e, context, &preExp, &varDecls, &auxFunction)
  case e as PARTEVALFUNCTION(__)then daeExpPartEvalFunction(e, context, &preExp, &varDecls, &auxFunction)
  case e as ARRAY(__)           then daeExpArray(e, context, &preExp, &varDecls, &auxFunction)
  case e as MATRIX(__)          then daeExpMatrix(e, context, &preExp, &varDecls, &auxFunction)
  case e as RANGE(__)           then daeExpRange(e, context, &preExp, &varDecls, &auxFunction)
  case e as CAST(__)            then daeExpCast(e, context, &preExp, &varDecls, &auxFunction)
  case e as ASUB(__)            then daeExpAsub(e, context, &preExp, &varDecls, &auxFunction)
  case e as TSUB(__)            then daeExpTsub(e, context, &preExp, &varDecls, &auxFunction)
  case e as RSUB(__)            then daeExpRsub(e, context, &preExp, &varDecls, &auxFunction)
  case e as SIZE(__)            then daeExpSize(e, context, &preExp, &varDecls, &auxFunction)
  case e as REDUCTION(__)       then daeExpReduction(e, context, &preExp, &varDecls, &auxFunction)
  case e as TUPLE(__)           then daeExpTuple(e, context, &preExp, &varDecls, &auxFunction)
  case e as LIST(__)            then daeExpList(e, context, &preExp, &varDecls, &auxFunction)
  case e as CONS(__)            then daeExpCons(e, context, &preExp, &varDecls, &auxFunction)
  case e as META_TUPLE(__)      then daeExpMetaTuple(e, context, &preExp, &varDecls, &auxFunction)
  case e as META_OPTION(__)     then daeExpMetaOption(e, context, &preExp, &varDecls, &auxFunction)
  case e as METARECORDCALL(__)  then daeExpMetarecordcall(e, context, &preExp, &varDecls, &auxFunction)
  case e as MATCHEXPRESSION(__) then daeExpMatch(e, context, &preExp, &varDecls, &auxFunction)
  case e as BOX(__)             then daeExpBox(e, context, &preExp, &varDecls, &auxFunction)
  case e as UNBOX(__)           then daeExpUnbox(e, context, &preExp, &varDecls, &auxFunction)
  case e as SHARED_LITERAL(__)  then daeExpSharedLiteral(e)
  case e as SUM(__)             then daeExpSum(e, context, &preExp, &varDecls, &auxFunction)
  case e as CLKCONST(__)        then '#error "<%ExpressionDump.printExpStr(e)%>"'
  else error(sourceInfo(), 'Unknown expression: <%ExpressionDump.printExpStr(exp)%>')
end daeExp;


template daeExternalCExp(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
  "Like daeExp, but also converts the type to external C"
::=
  match typeof(exp)
    case T_ARRAY(__) then  // Array-expressions
      let shortTypeStr = expTypeShort(typeof(exp))
      '(<%extType(typeof(exp),true,true)%>) data_of_<%shortTypeStr%>_array(&<%daeExp(exp, context, &preExp, &varDecls, &auxFunction)%>)'
    case T_STRING(__) then
      let mstr = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
      'MMC_STRINGDATA(<%mstr%>)'
    else daeExp(exp, context, &preExp, &varDecls, &auxFunction)
end daeExternalCExp;

template daeExternalF77Exp(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
  "Like daeExp, but also converts the type to external Fortran"
::=
  match typeof(exp)
    case T_ARRAY(__) then  // Array-expressions
      let shortTypeStr = expTypeShort(typeof(exp))
      '(<%extType(typeof(exp),true,true)%>) data_of_<%shortTypeStr%>_array(&<%daeExp(exp, context, &preExp, &varDecls, &auxFunction)%>)'
    case T_STRING(__) then
      let texp = daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
      let tvar = tempDecl(expTypeFromExpFlag(exp,8),&varDecls)
      let &preExp += '<%tvar%> = MMC_STRINGDATA(<%texp%>);<%\n%>'
      '&<%tvar%>'
    else
      let texp = daeExp(exp, contextFunction, &preExp, &varDecls, &auxFunction)
      let tvar = tempDecl(expTypeFromExpFlag(exp,8),&varDecls)
      let &preExp += '<%tvar%> = <%texp%>;<%\n%>'
      '&<%tvar%>'
end daeExternalF77Exp;

template daeExpSconst(String string, Text &preExp, Text &varDecls)
 "Generates code for a string constant."
::=
  let escstr = Util.escapeModelicaStringToCString(string)
  match stringLength(string)
    case 0 then "(modelica_string) mmc_emptystring"
    case 1 then '(modelica_string) mmc_strings_len1[<%stringGet(string, 1)%>]'
    else
      let tmp = 'tmp<%System.tmpTick()%>'
      let &varDecls += 'static const MMC_DEFSTRINGLIT(<%tmp%>,<%unescapedStringLength(escstr)%>,"<%escstr%>");<%\n%>'
      'MMC_REFSTRINGLIT(<%tmp%>)'
end daeExpSconst;

template daeExpList(Exp exp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica list expression."
::=
match exp
case LIST(__) then
  let tmp = tempDecl("modelica_metatype", &varDecls)
  let expPart = daeExpListToCons(valList, context, &preExp, &varDecls, &auxFunction)
  let &preExp += '<%tmp%> = <%expPart%>;<%\n%>'
  tmp
end daeExpList;


template daeExpListToCons(list<Exp> listItems, Context context, Text &preExp,
                          Text &varDecls, Text &auxFunction)
 "Helper to daeExpList."
::=
  match listItems
  case {} then "MMC_REFSTRUCTLIT(mmc_nil)"
  case e :: rest then
    let expPart = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    let restList = daeExpListToCons(rest, context, &preExp, &varDecls, &auxFunction)
    <<
    mmc_mk_cons(<%expPart%>, <%restList%>)
    >>
end daeExpListToCons;


template daeExpCons(Exp exp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica cons expression."
::=
match exp
case CONS(__) then
  let tmp = tempDecl("modelica_metatype", &varDecls)
  let carExp = daeExp(car, context, &preExp, &varDecls, &auxFunction)

  let cdrExp = daeExp(cdr, context, &preExp, &varDecls, &auxFunction)
  let &preExp += '<%tmp%> = mmc_mk_cons(<%carExp%>, <%cdrExp%>);<%\n%>'
  tmp
end daeExpCons;

template tempDeclTuple(DAE.Type inType, Text &varDecls)
::=
  match inType
  case T_TUPLE(__) then
  let tmpVar = 'tmp<%System.tmpTick()%>'
  let &varDecls +=
  <<
  struct {
    <%types |> ty hasindex i1 fromindex 1 => '<%expTypeModelica(ty)%> c<%i1%>;<%\n%>'%>
  } <%tmpVar%>;
  >>
  tmpVar
  else tempDecl(expTypeArrayIf(inType),&varDecls)
end tempDeclTuple;

template daeExpTuple(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica tuple expression."
::=
match exp
case TUPLE(__) then
  let tmpVar = tempDeclTuple(typeof(exp),&varDecls)
  let tmp = (PR |> e hasindex i1 fromindex 1 => '<%tmpVar%>.c<%i1%> = <%daeExp(e, context, &preExp, &varDecls, &auxFunction)%>;<%\n%>')
  let &preExp += tmp
  tmpVar
end daeExpTuple;

template daeExpMetaTuple(Exp exp, Context context, Text &preExp,
                         Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica tuple expression."
::=
match exp
case META_TUPLE(__) then
  let start = daeExpMetaHelperBoxStart(listLength(listExp))
  let args = (listExp |> e => daeExp(e, context, &preExp, &varDecls, &auxFunction)
    ;separator=", ")
  let tmp = tempDecl("modelica_metatype", &varDecls)
  let &preExp += '<%tmp%> = mmc_mk_box<%start%>0<%if args then ", "%><%args%>);<%\n%>'
  tmp
end daeExpMetaTuple;


template daeExpMetaOption(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica option expression."
::=
  match exp
  case META_OPTION(exp=NONE()) then
    "mmc_mk_none()"
  case META_OPTION(exp=SOME(e)) then
    let expPart = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    'mmc_mk_some(<%expPart%>)'
end daeExpMetaOption;


template daeExpMetarecordcall(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a meta modelica record call expression."
::=
match exp
case METARECORDCALL(__) then
  let newIndex = getValueCtor(index)
  let argsStr = if args then
      ', <%args |> exp =>
        daeExp(exp, context, &preExp, &varDecls, &auxFunction)
      ;separator=", "%>'
    else
      ""
  let box = 'mmc_mk_box<%daeExpMetaHelperBoxStart(incrementInt(listLength(args), 1))%><%newIndex%>, &<%underscorePath(path)%>__desc<%argsStr%>)'
  let tmp = tempDecl("modelica_metatype", &varDecls)
  let &preExp += '<%tmp%> = <%box%>;<%\n%>'
  tmp
end daeExpMetarecordcall;

template daeExpMetaHelperBoxStart(Integer numVariables)
 "Helper to determine how mmc_mk_box should be called."
::=
  if intGt(numVariables,20) then '(<%numVariables%>, ' else '<%numVariables%>('
end daeExpMetaHelperBoxStart;

template crefToMStr(ComponentRef cr)
 "Helper function to crefM."
::=
  match cr
  case CREF_IDENT(__) then '<%unquoteIdentifier(ident)%><%subscriptsToMStr(subscriptLst)%>'
  case CREF_QUAL(__) then '<%unquoteIdentifier(ident)%><%subscriptsToMStr(subscriptLst)%>P<%crefToMStr(componentRef)%>'
  else "CREF_NOT_IDENT_OR_QUAL"
end crefToMStr;

template subscriptsToMStr(list<Subscript> subscripts)
::=
  if subscripts then
    'lB<%subscripts |> s => subscriptToMStr(s) ;separator="c"%>rB'
end subscriptsToMStr;

template subscriptToMStr(Subscript subscript)
::=
  match subscript
  case SLICE(exp=ICONST(integer=i)) then i
  case SLICE(__) then error(sourceInfo(), "Unknown slice " + printExpStr(exp))
  case WHOLEDIM(__) then "WHOLEDIM"
  case INDEX(__) then
   match exp
    case ICONST(integer=i) then i
    case ENUM_LITERAL(index=i) then i
    else
      let &varDecls = buffer ""
      let &preExp = buffer ""
      let &auxFunction = buffer ""
      daeExp(exp, contextOther, &preExp, &varDecls, &auxFunction)
   end match
  else error(sourceInfo(), "UNKNOWN_SUBSCRIPT")
end subscriptToMStr;

template generateThrow()
::=
  match codegenPeekTryThrowIndex()
  case -1 then "MMC_THROW_INTERNAL()"
  case i then 'goto goto_<%i%>'
end generateThrow;

template daeExpCrefRhs(Exp exp, Context context, Text &preExp,
                       Text &varDecls, Text &auxFunction)
 "Generates code for a component reference on the right hand side of an
 expression."
::=
  match exp
  case CREF(componentRef = cr, ty = T_FUNCTION_REFERENCE_FUNC(__)) then
    'boxvar_<%crefFunctionName(cr)%>'
  case CREF(componentRef = cr, ty = T_FUNCTION_REFERENCE_VAR(__)) then
    '((modelica_fnptr) _<%crefStr(cr)%>)'
  case CREF(componentRef = cr as CREF_QUAL(subscriptLst={}, identType = T_METATYPE(ty=ty as T_METAUNIONTYPE(__)), componentRef=cri as CREF_IDENT(__)))
  case CREF(componentRef = cr as CREF_QUAL(subscriptLst={}, identType = T_METATYPE(ty=ty as T_METARECORD(__)), componentRef=cri as CREF_IDENT(__))) then
    let offset = intAdd(findVarIndex(cri.ident,getMetaRecordFields(ty)),2) // 0-based
    '(MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(_<%cr.ident%>), <%offset%>)))'
  else
    match context
    case FUNCTION_CONTEXT(__) then daeExpCrefRhsFunContext(exp, context, &preExp, &varDecls, &auxFunction)
    case PARALLEL_FUNCTION_CONTEXT(__) then daeExpCrefRhsFunContext(exp, context, &preExp, &varDecls, &auxFunction)
    else daeExpCrefRhsSimContext(exp, context, &preExp, &varDecls, &auxFunction)
end daeExpCrefRhs;

template daeExpCrefRhsSimContext(Exp ecr, Context context, Text &preExp,
                        Text &varDecls, Text &auxFunction)
 "Generates code for a component reference in simulation context."
::=
  match ecr
  case ecr as CREF(componentRef = cr, ty = t as T_COMPLEX(complexClassType = EXTERNAL_OBJ(__))) then
    contextCref(cr, context, &auxFunction)

  case ecr as CREF(componentRef = cr, ty = t as T_COMPLEX(complexClassType = record_state, varLst = var_lst)) then
    let vars = var_lst |> v => (", " + daeExp(makeCrefRecordExp(cr,v), context, &preExp, &varDecls, &auxFunction))
    let record_type_name = underscorePath(ClassInf.getStateName(record_state))
    'omc_<%record_type_name%>(threadData<%vars%>)'

  case ecr as CREF(componentRef=cr, ty=T_ARRAY(ty=aty, dims=dims)) then
    let type = expTypeShort(aty)
    let arrayType = type + "_array"
    let wrapperArray = tempDecl(arrayType, &varDecls)
    if crefSubIsScalar(cr) then
      let dimsLenStr = listLength(dims)
      let dimsValuesStr = (dims |> dim => dimension(dim) ;separator=", ")
      let nosubname = contextCref(crefStripSubs(cr),context, &auxFunction)
      let substring = (crefSubs(crefArrayGetFirstCref(cr)) |> INDEX(__) =>
                   daeSubscriptExp(exp, context, &preExp, &varDecls, &auxFunction)
                   ;separator=", ")
      let &preExp += '<%type%>_array_create(&<%wrapperArray%>, ((modelica_<%type%>*)&(<%nosubname%>_index(<%substring%>))), <%dimsLenStr%>, <%dimsValuesStr%>);<%\n%>'
    wrapperArray
    else
      let dimsLenStr = listLength(crefDims(cr))
      let dimsValuesStr = (crefDims(cr) |> dim => dimension(dim) ;separator=", ")
      let arrName = contextCref(crefStripSubs(cr), context,&auxFunction)
      let &preExp += '<%type%>_array_create(&<%wrapperArray%>, (modelica_<%type%>*)&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>);<%\n%>'
      let slicedArray = tempDecl(arrayType, &varDecls)
      let spec1 = daeExpCrefIndexSpec(crefSubs(cr), context, &preExp, &varDecls, &auxFunction)
      let &preExp += 'index_alloc_<%type%>_array(&<%wrapperArray%>, &<%spec1%>, &<%slicedArray%>);<%\n%>'
    slicedArray

  case ecr as CREF(componentRef=cr, ty=ty) then
    if crefIsScalarWithAllConstSubs(cr) then
      let cast = match ty case T_INTEGER(__) then "(modelica_integer)"
                          case T_ENUMERATION(__) then "(modelica_integer)" //else ""
        '<%cast%><%contextCref(cr,context, &auxFunction)%>'
    else if crefIsScalarWithVariableSubs(cr) then
      let nosubname = contextCref(crefStripSubs(cr),context, &auxFunction)
      let substring = (crefSubs(cr) |> INDEX(__) =>
                 daeSubscriptExp(exp, context, &preExp, &varDecls, &auxFunction)
                 ;separator=", ")
      let cast = match ty case T_INTEGER(__) then "(modelica_integer)"
                          case T_ENUMERATION(__) then "(modelica_integer)" //else ""
        '<%cast%><%nosubname%>_index(<%substring%>)'
    else
      error(sourceInfo(),'daeExpCrefRhsSimContext: UNHANDLED CREF: <%ExpressionDump.printExpStr(ecr)%>')
end daeExpCrefRhsSimContext;

template daeExpCrefRhsFunContext(Exp ecr, Context context, Text &preExp,
                        Text &varDecls, Text &auxFunction)
 "Generates code for a component reference."
::=
  match ecr
  case ecr as CREF(componentRef=cr, ty=ty) then
    if crefIsScalar(cr, context) then
      let cast = match ty case T_INTEGER(__) then "(modelica_integer)"
                        case T_ENUMERATION(__) then "(modelica_integer)" //else ""
      '<%cast%><%contextCref(cr,context, &auxFunction)%>'
    else
      if crefSubIsScalar(cr) then
        // The array subscript results in a scalar
        let arrName = contextCref(crefStripLastSubs(cr), context, &auxFunction)
        let arrayType = expTypeArray(ty)
        let dimsLenStr = listLength(crefSubs(cr))
        let dimsValuesStr = (crefSubs(cr) |> INDEX(__) =>
            daeDimensionExp(exp, context, &preExp, &varDecls, &auxFunction)
            ;separator=", ")
        match cr
          case CREF_IDENT(identType = T_METATYPE(ty = T_METAARRAY()))
          case CREF_IDENT(identType = T_METAARRAY()) then
            'arrayGet(<%arrName%>, <%dimsValuesStr%>)'
          else
            match context
              case FUNCTION_CONTEXT(__) then
                match ty
                  case (T_ARRAY(ty = T_COMPLEX(complexClassType = record_state)))
                  case (T_COMPLEX(complexClassType = record_state)) then
                    let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
                    <<
                     (*((<%rec_name%>*)(generic_array_element_addr(&<%arrName%>, sizeof(<%rec_name%>), <%dimsLenStr%>, <%dimsValuesStr%>))))
                    >>
                  else
                    <<
                    (*<%arrayType%>_element_addr(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
                    >>
              case PARALLEL_FUNCTION_CONTEXT(__) then
                <<
                (*<%arrayType%>_element_addr_c99_<%dimsLenStr%>(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
                >>
              else
                error(sourceInfo(),'This should have been handled in the new daeExpCrefRhsSimContext function. <%printExpStr(ecr)%>')
      else
        match context
        case FUNCTION_CONTEXT(__)
        case PARALLEL_FUNCTION_CONTEXT(__) then
          // The array subscript denotes a slice
          // let &preExp += '/* daeExpCrefRhsFunContext SLICE(<%ExpressionDump.printExpStr(ecr)%>) preExp  */<%\n%>'
          let arrName = contextArrayCref(cr, context)
          let arrayType = expTypeArray(ty)
          let tmp = tempDecl(arrayType, &varDecls)
          let spec1 = daeExpCrefIndexSpec(crefSubs(cr), context, &preExp, &varDecls, &auxFunction)
          let &preExp += 'index_alloc_<%arrayType%>(&<%arrName%>, &<%spec1%>, &<%tmp%>);<%\n%>'
          tmp
        else
          error(sourceInfo(),'daeExpCrefRhsFunContext: Slice in simulation context: <%ExpressionDump.printExpStr(ecr)%>')
  case ecr then
    error(sourceInfo(),'daeExpCrefRhsFunContext: UNHANDLED EXPRESSION: <%ExpressionDump.printExpStr(ecr)%>')
end daeExpCrefRhsFunContext;

// TODO: Optimize as in Codegen
// TODO: Use this function in other places where almost the same thing is hard
//       coded
template arrayScalarRhs(Type ty, list<Exp> subs, String arrName, Context context,
               Text &preExp, Text &varDecls, Text &auxFunction)
 "Helper to daeExpAsub."
::=
  let arrayType = expTypeArray(ty)
  let dimsLenStr = listLength(subs)
  let dimsValuesStr = (subs |> exp =>
      daeDimensionExp(exp, context, &preExp, &varDecls, &auxFunction)

    ;separator=", ")
  match arrayType
    case "metatype_array" then
      'arrayGet(<%arrName%>,<%dimsValuesStr%>) /*arrayScalarRhs*/'
    else
    match context
        case PARALLEL_FUNCTION_CONTEXT(__) then
          <<
          (*<%arrayType%>_element_addr_c99_<%dimsLenStr%>(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
          >>
        else
          <<
          (*<%arrayType%>_element_addr(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
          >>
end arrayScalarRhs;

template daeExpCrefLhs(Exp exp, Context context, Text &preExp,
                       Text &varDecls, Text &auxFunction)
 "Generates code for a component reference on the left hand side of an expression."
::=
  match exp
  case CREF(componentRef = cr, ty = T_FUNCTION_REFERENCE_FUNC(__)) then
    '((modelica_fnptr)boxptr_<%crefFunctionName(cr)%>)'
  case CREF(componentRef = cr, ty = T_FUNCTION_REFERENCE_VAR(__)) then
    '_<%crefStr(cr)%>'
  else
    match context
    case FUNCTION_CONTEXT(__) then daeExpCrefLhsFunContext(exp, context, &preExp, &varDecls, &auxFunction)
    case PARALLEL_FUNCTION_CONTEXT(__) then daeExpCrefLhsFunContext(exp, context, &preExp, &varDecls, &auxFunction)
    else daeExpCrefLhsSimContext(exp, context, &preExp, &varDecls, &auxFunction)
end daeExpCrefLhs;

template daeExpCrefLhsSimContext(Exp ecr, Context context, Text &preExp,
                        Text &varDecls, Text &auxFunction)
 "Generates code for a component reference in simulation context."
::=
  match ecr
  case ecr as CREF(componentRef = cr, ty = t as T_COMPLEX(complexClassType = EXTERNAL_OBJ(__))) then
    contextCref(cr, context, &auxFunction)

  case ecr as CREF(componentRef = cr, ty = t as T_COMPLEX(complexClassType = record_state, varLst = var_lst)) then
    let vars = var_lst |> v => (", " + daeExp(makeCrefRecordExp(cr,v), context, &preExp, &varDecls, &auxFunction))
    let record_type_name = underscorePath(ClassInf.getStateName(record_state))
    // 'omc_<%record_type_name%>(threadData<%vars%>)'
    error(sourceInfo(), 'daeExpCrefLhsSimContext got record <%crefStr(cr)%>. This does not make sense. Assigning to records is handled in a different way in the code generator, and reaching here is probably an error...') // '<%ret_var%>.c1'

  case ecr as CREF(componentRef=cr, ty=T_ARRAY(ty=aty, dims=dims)) then
    let type = expTypeShort(aty)
    let arrayType = type + "_array"
    let wrapperArray = tempDecl(arrayType, &varDecls)
    if crefSubIsScalar(cr) then
      let dimsLenStr = listLength(dims)
      let dimsValuesStr = (dims |> dim => dimension(dim) ;separator=", ")
      let nosubname = contextCref(crefStripSubs(cr),context, &auxFunction)
      let substring = (crefSubs(crefArrayGetFirstCref(cr)) |> INDEX(__) =>
                   daeSubscriptExp(exp, context, &preExp, &varDecls, &auxFunction)
                   ;separator=", ")
      let &preExp += '<%type%>_array_create(&<%wrapperArray%>, ((modelica_<%type%>*)&(<%nosubname%>_index(<%substring%>))), <%dimsLenStr%>, <%dimsValuesStr%>);<%\n%>'
    wrapperArray
    else
        error(sourceInfo(),'daeExpCrefLhsSimContext: This should have been handled in indexed assign and should not have gotten here <%ExpressionDump.printExpStr(ecr)%>')


  case ecr as CREF(componentRef=cr, ty=ty) then
    if crefIsScalarWithAllConstSubs(cr) then
        '<%contextCref(cr,context, &auxFunction)%>'
    else if crefIsScalarWithVariableSubs(cr) then
      let nosubname = contextCref(crefStripSubs(cr),context, &auxFunction)
      let substring = (crefSubs(cr) |> INDEX(__) =>
                 daeSubscriptExp(exp, context, &preExp, &varDecls, &auxFunction)
                 ;separator=", ")
        '<%nosubname%>_index(<%substring%>)'
    else
      error(sourceInfo(),'daeExpCrefLhsSimContext: UNHANDLED CREF: <%ExpressionDump.printExpStr(ecr)%>')
end daeExpCrefLhsSimContext;

template daeExpCrefLhsFunContext(Exp ecr, Context context, Text &preExp,
                        Text &varDecls, Text &auxFunction)
 "Generates code for a component reference on the left hand side!"
::=
  match ecr
  case ecr as CREF(componentRef=cr, ty=ty) then
    if crefIsScalar(cr, context) then
      '<%contextCref(cr,context,&auxFunction)%>'
    else
      if crefSubIsScalar(cr) then
        // The array subscript results in a scalar
        let arrName = contextCref(crefStripLastSubs(cr), context, &auxFunction)
        let arrayType = expTypeArray(ty)
        let dimsLenStr = listLength(crefSubs(cr))
        let dimsValuesStr = (crefSubs(cr) |> INDEX(__) =>
            daeDimensionExp(exp, context, &preExp, &varDecls, &auxFunction)
          ;separator=", ")
        match context
          case PARALLEL_FUNCTION_CONTEXT(__) then
               <<
               (*<%arrayType%>_element_addr_c99_<%dimsLenStr%>(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
               >>
           case FUNCTION_CONTEXT(__) then
               <<
               (*<%arrayType%>_element_addr(&<%arrName%>, <%dimsLenStr%>, <%dimsValuesStr%>))
               >>
           else
             error(sourceInfo(),'This should have been handled in the new daeExpCrefLhsSimContext function. <%printExpStr(ecr)%>')

      else
        error(sourceInfo(),'This should have been handled in indexed assign and should not have gotten here. <%printExpStr(ecr)%>')

  case ecr then
    error(sourceInfo(), 'SimCodeC.tpl template: daeExpCrefLhsFunContext: UNHANDLED EXPRESSION:  <%ExpressionDump.printExpStr(ecr)%>')
end daeExpCrefLhsFunContext;

template daeExpCrefIndexSpec(list<Subscript> subs, Context context,
                                Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates index lists for crefs involving slices"
::=
  let nridx_str = listLength(subs)
  let idx_str = (subs |> sub =>
      match sub
      case INDEX(__) then
        let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
        let str = <<(0), make_index_array(1, (int) <%expPart%>), 'S'>>
        str
      case WHOLEDIM(__) then
        let str = <<(1), (int*)0, 'W'>>
        str
      case SLICE(__) then
        let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
        let tmp = tempDecl("modelica_integer", &varDecls)
        let &preExp += '<%tmp%> = size_of_dimension_base_array(<%expPart%>, 1);<%\n%>'
        let str = <<(int) <%tmp%>, integer_array_make_index_array(&<%expPart%>), 'A'>>
        str
    ;separator=", ")
  let tmp = tempDecl("index_spec_t", &varDecls)
  let &preExp += 'create_index_spec(&<%tmp%>, <%nridx_str%>, <%idx_str%>);<%\n%>'
  tmp
end daeExpCrefIndexSpec;

template daeExpBinary(Exp exp, Context context, Text &preExp,
                      Text &varDecls, Text &auxFunction)
 "Generates code for a binary expression."
::=

match exp
case BINARY(__) then
  let e1 = daeExp(exp1, context, &preExp, &varDecls, &auxFunction)
  let e2 = daeExp(exp2, context, &preExp, &varDecls, &auxFunction)
  match operator
  case ADD(ty = T_STRING(__)) then
    let tmpStr = tempDecl("modelica_metatype", &varDecls)
    let &preExp += '<%tmpStr%> = stringAppend(<%e1%>,<%e2%>);<%\n%>'
    tmpStr
  case ADD(__) then '(<%e1%> + <%e2%>)'
  case SUB(__) then '(<%e1%> - <%e2%>)'
  case MUL(__) then '(<%e1%> * <%e2%>)'
  case DIV(__) then
    let tvar = tempDecl(expTypeModelica(ty),&varDecls)
    let &preExp += '<%tvar%> = <%e2%>;<%\n%>'
    let &preExp +=
      if acceptMetaModelicaGrammar()
        then 'if (<%tvar%> == 0) {<%generateThrow()%>;}<%\n%>'
        else 'if (<%tvar%> == 0) {throwStreamPrint(threadData, "Division by zero %s", "<%Util.escapeModelicaStringToCString(printExpStr(exp))%>");}<%\n%>'
    '(<%e1%> / <%e2%>)'
  case POW(__) then
    if isHalf(exp2) then
      (let tmp = tempDecl(expTypeFromExpModelica(exp1),&varDecls)
       let ass = '(<%tmp%> >= 0.0)'
       let &preExpMsg = buffer ""
       let retPre = assertCommonVar(ass,'"Model error: Argument of sqrt(<%Util.escapeModelicaStringToCString(printExpStr(exp1))%>) was %g should be >= 0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
       let &preExp += '<%tmp%> = <%e1%>; <%\n%><%retPre%>'
       'sqrt(<%tmp%>)')
    else match realExpIntLit(exp2)
      case SOME(2) then
        let tmp = tempDecl("modelica_real", &varDecls)
        let &preExp += '<%tmp%> = <%e1%>;<%\n%>'
        '(<%tmp%> * <%tmp%>)'
      case SOME(3) then
        let tmp = tempDecl("modelica_real", &varDecls)
        let &preExp += '<%tmp%> = <%e1%>;<%\n%>'
        '(<%tmp%> * <%tmp%> * <%tmp%>)'
      case SOME(4) then
        let tmp = tempDecl("modelica_real", &varDecls)
        let &preExp += '<%tmp%> = <%e1%>;<%\n%>'
        let &preExp += '<%tmp%> *= <%tmp%>;<%\n%>'
        '(<%tmp%> * <%tmp%>)'
      case SOME(i) then 'real_int_pow(threadData, <%e1%>, <%i%>)'
      else 'pow(<%e1%>, <%e2%>)'
  case UMINUS(__) then daeExpUnary(exp, context, &preExp, &varDecls, &auxFunction)
  case ADD_ARR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'add_alloc_<%type%>(<%e1%>, <%e2%>)'
  case SUB_ARR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'sub_alloc_<%type%>(<%e1%>, <%e2%>)'
  case MUL_ARR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'mul_alloc_<%type%>(<%e1%>, <%e2%>)'
  case DIV_ARR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'div_alloc_<%type%>(<%e1%>, <%e2%>)'
  case MUL_ARRAY_SCALAR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'mul_alloc_<%type%>_scalar(<%e1%>, <%e2%>)'
  case ADD_ARRAY_SCALAR(__) then error(sourceInfo(),'Code generation does not support ADD_ARRAY_SCALAR <%printExpStr(exp)%>')
  case SUB_SCALAR_ARRAY(__) then error(sourceInfo(),'Code generation does not support SUB_SCALAR_ARRAY <%printExpStr(exp)%>')
  case MUL_SCALAR_PRODUCT(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_scalar"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_scalar"
                        case T_INTEGER(__) then "integer_scalar"
                        case T_ENUMERATION(__) then "integer_scalar"
                        else "real_scalar"
    'mul_<%type%>_product(<%e1%>, <%e2%>)'
  case MUL_MATRIX_PRODUCT(__) then
    let typeShort = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer"
                             case T_ARRAY(ty=T_ENUMERATION(__)) then "integer"
                             else "real"
    let type = '<%typeShort%>_array'
    'mul_alloc_<%typeShort%>_matrix_product_smart(<%e1%>, <%e2%>)'
  case DIV_ARRAY_SCALAR(__) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'div_alloc_<%type%>_scalar(<%e1%>, <%e2%>)'
  case DIV_SCALAR_ARRAY(__) then
    let type = match ty case T_ARRAY(ty = T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty = T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'div_alloc_scalar_<%type%>(<%e1%>, <%e2%>)'
  case POW_ARRAY_SCALAR(__) then
    let type = match ty case T_ARRAY(ty = T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty = T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    'pow_alloc_<%type%>_scalar(<%e1%>, <%e2%>)'
  case POW_ARRAY_SCALAR(__) then 'daeExpBinary:ERR for POW_ARRAY_SCALAR'
  case POW_SCALAR_ARRAY(__) then 'daeExpBinary:ERR for POW_SCALAR_ARRAY'
  case POW_ARR(__) then 'daeExpBinary:ERR for POW_ARR'
  case POW_ARR2(__) then 'daeExpBinary:ERR for POW_ARR2'
  else error(sourceInfo(), 'daeExpBinary:ERR')
end daeExpBinary;


template daeExpUnary(Exp exp, Context context, Text &preExp,
                     Text &varDecls, Text &auxFunction)
 "Generates code for a unary expression."
::=
match exp
case UNARY(__) then
  let e = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  match operator
  case UMINUS(__)     then '(-<%e%>)'
  case UMINUS_ARR(ty=T_ARRAY(ty=T_REAL(__))) then
    let var = tempDecl("real_array", &varDecls)
    let &preExp += 'usub_alloc_real_array(<%e%>,&<%var%>);<%\n%>'
    '<%var%>'
  case UMINUS_ARR(ty=T_ARRAY(ty=T_INTEGER(__))) then
    let var = tempDecl("integer_array", &varDecls)
    let &preExp += 'usub_alloc_integer_array(<%e%>,&<%var%>);<%\n%>'
    '<%var%>'
  case UMINUS_ARR(__) then error(sourceInfo(),"unary minus for non-real arrays not implemented")
  else error(sourceInfo(),"daeExpUnary:ERR")
end daeExpUnary;


template daeExpLbinary(Exp exp, Context context, Text &preExp,
                       Text &varDecls, Text &auxFunction)
 "Generates code for a logical binary expression."
::=
match exp
case LBINARY(__) then
  let e1 = daeExp(exp1, context, &preExp, &varDecls, &auxFunction)
  let e2 = daeExp(exp2, context, &preExp, &varDecls, &auxFunction)
  match operator
  case AND(ty = T_ARRAY(__)) then
    let var = tempDecl("boolean_array", &varDecls)
    let &preExp += 'and_boolean_array(&<%e1%>,&<%e2%>,&<%var%>);<%\n%>'
    '<%var%>'
  case AND(__) then
    '(<%e1%> && <%e2%>)'
  case OR(ty = T_ARRAY(__)) then
    let var = tempDecl("boolean_array", &varDecls)
    let &preExp += 'or_boolean_array(&<%e1%>,&<%e2%>,&<%var%>);<%\n%>'
    '<%var%>'
  case OR(__) then
    '(<%e1%> || <%e2%>)'
  else error(sourceInfo(),"daeExpLbinary:ERR")
end daeExpLbinary;


template daeExpLunary(Exp exp, Context context, Text &preExp,
                      Text &varDecls, Text &auxFunction)
 "Generates code for a logical unary expression."
::=
match exp
case LUNARY(__) then
  let e = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  match operator
  case NOT(ty = T_ARRAY(__)) then
    let var = tempDecl("boolean_array", &varDecls)
    let &preExp += 'not_boolean_array(<%e%>,&<%var%>);<%\n%>'
    '<%var%>'
  else
    '(!<%e%>)'
end daeExpLunary;


template daeExpRelation(Exp exp, Context context, Text &preExp,
                        Text &varDecls, Text &auxFunction)
 "Generates code for a relation expression."
::=
match exp
case rel as RELATION(__) then
  let &varDecls2 = buffer ""
  let &preExp2 = buffer ""
  let simRel = daeExpRelationSim(rel, context, &preExp2, &varDecls2, &auxFunction)
  if simRel then
    /* Don't add the allocated temp-var unless it is used */
    let &varDecls += varDecls2
    let &preExp += preExp2
    simRel
  else
    let e1 = daeExp(rel.exp1, context, &preExp, &varDecls, &auxFunction)
    let e2 = daeExp(rel.exp2, context, &preExp, &varDecls, &auxFunction)
    match rel.operator

    case LESS(ty = T_BOOL(__))             then '(!<%e1%> && <%e2%>)'
    case LESS(ty = T_STRING(__))           then '(stringCompare(<%e1%>, <%e2%>) < 0)'
    case LESS(ty = T_INTEGER(__))              then '(<%e1%> < <%e2%>)'
    case LESS(ty = T_REAL(__))             then '(<%e1%> < <%e2%>)'
    case LESS(ty = T_ENUMERATION(__))      then '(<%e1%> < <%e2%>)'

    case GREATER(ty = T_BOOL(__))          then '(<%e1%> && !<%e2%>)'
    case GREATER(ty = T_STRING(__))        then '(stringCompare(<%e1%>, <%e2%>) > 0)'
    case GREATER(ty = T_INTEGER(__))           then '(<%e1%> > <%e2%>)'
    case GREATER(ty = T_REAL(__))          then '(<%e1%> > <%e2%>)'
    case GREATER(ty = T_ENUMERATION(__))   then '(<%e1%> > <%e2%>)'

    case LESSEQ(ty = T_BOOL(__))           then '(!<%e1%> || <%e2%>)'
    case LESSEQ(ty = T_STRING(__))         then '(stringCompare(<%e1%>, <%e2%>) <= 0)'
    case LESSEQ(ty = T_INTEGER(__))            then '(<%e1%> <= <%e2%>)'
    case LESSEQ(ty = T_REAL(__))           then '(<%e1%> <= <%e2%>)'
    case LESSEQ(ty = T_ENUMERATION(__))    then '(<%e1%> <= <%e2%>)'

    case GREATEREQ(ty = T_BOOL(__))        then '(<%e1%> || !<%e2%>)'
    case GREATEREQ(ty = T_STRING(__))      then '(stringCompare(<%e1%>, <%e2%>) >= 0)'
    case GREATEREQ(ty = T_INTEGER(__))         then '(<%e1%> >= <%e2%>)'
    case GREATEREQ(ty = T_REAL(__))        then '(<%e1%> >= <%e2%>)'
    case GREATEREQ(ty = T_ENUMERATION(__)) then '(<%e1%> >= <%e2%>)'

    case EQUAL(ty = T_BOOL(__))            then '((!<%e1%> && !<%e2%>) || (<%e1%> && <%e2%>))'
    case EQUAL(ty = T_STRING(__))          then '(stringEqual(<%e1%>, <%e2%>))'
    case EQUAL(ty = T_INTEGER(__))             then '(<%e1%> == <%e2%>)'
    case EQUAL(ty = T_REAL(__))            then '(<%e1%> == <%e2%>)'
    case EQUAL(ty = T_ENUMERATION(__))     then '(<%e1%> == <%e2%>)'
    case EQUAL(ty = T_ARRAY(__))           then '<%e2%>' /* Used for Boolean array. Called from daeExpLunary. */

    case NEQUAL(ty = T_BOOL(__))           then '((!<%e1%> && <%e2%>) || (<%e1%> && !<%e2%>))'
    case NEQUAL(ty = T_STRING(__))         then '(!stringEqual(<%e1%>, <%e2%>))'
    case NEQUAL(ty = T_INTEGER(__))            then '(<%e1%> != <%e2%>)'
    case NEQUAL(ty = T_REAL(__))           then '(<%e1%> != <%e2%>)'
    case NEQUAL(ty = T_ENUMERATION(__))    then '(<%e1%> != <%e2%>)'

    else error(sourceInfo(), 'daeExpRelation <%printExpStr(exp)%>')
end daeExpRelation;



template daeExpRelationSim(Exp exp, Context context, Text &preExp,
                           Text &varDecls, Text &auxFunction)
 "Helper to daeExpRelation."
::=
match exp
case rel as RELATION(__) then
  match context
  case SIMULATION_CONTEXT(__) then
    match rel.optionExpisASUB
    case NONE() then
      let e1 = daeExp(rel.exp1, context, &preExp, &varDecls, &auxFunction)
      let e2 = daeExp(rel.exp2, context, &preExp, &varDecls, &auxFunction)
      let res = tempDecl("modelica_boolean", &varDecls)
      if intEq(rel.index,-1) then
        match rel.operator
        case LESS(__) then
          let &preExp += '<%res%> = Less(<%e1%>,<%e2%>);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%res%> = LessEq(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%res%> = Greater(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%res%> = GreaterEq(<%e1%>,<%e2%>);<%\n%>'
          res
        end match
      else
        let isReal = if isRealType(typeof(rel.exp1)) then (if isRealType(typeof(rel.exp2)) then 'true' else '') else ''
        let hysteresisfunction = if isReal then 'RELATIONHYSTERESIS' else 'RELATION'
        match rel.operator
        case LESS(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%>, Less);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%>, LessEq);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%>, Greater);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%>, GreaterEq);<%\n%>'
          res
        end match
    case SOME((exp,i,j)) then
      let e1 = daeExp(rel.exp1, context, &preExp, &varDecls, &auxFunction)
      let e2 = daeExp(rel.exp2, context, &preExp, &varDecls, &auxFunction)
      let iterator = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
      let res = tempDecl("modelica_boolean", &varDecls)
      if intEq(rel.index,-1) then
        match rel.operator
        case LESS(__) then
          let &preExp += '<%res%> = Less(<%e1%>,<%e2%>);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%res%> = LessEq(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%res%> = Greater(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%res%> = GreaterEq(<%e1%>,<%e2%>);<%\n%>'
          res
        end match
      else
        let isReal = if isRealType(typeof(rel.exp1)) then (if isRealType(typeof(rel.exp2)) then 'true' else '') else ''
        let hysteresisfunction = if isReal then 'RELATIONHYSTERESIS' else 'RELATION'
        match rel.operator
        case LESS(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%> + (<%iterator%> - <%i%>)/<%j%>, Less);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%> + (<%iterator%> - <%i%>)/<%j%>, LessEq);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%> + (<%iterator%> - <%i%>)/<%j%>, Greater);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%hysteresisfunction%>(<%res%>, <%e1%>, <%e2%>, <%rel.index%> + (<%iterator%> - <%i%>)/<%j%>, GreaterEq);<%\n%>'
          res
        end match
    end match
  case ZEROCROSSINGS_CONTEXT(__) then
    match rel.optionExpisASUB
    case NONE() then
      let e1 = daeExp(rel.exp1, context, &preExp, &varDecls, &auxFunction)
      let e2 = daeExp(rel.exp2, context, &preExp, &varDecls, &auxFunction)
      let res = tempDecl("modelica_boolean", &varDecls)
      if intEq(rel.index,-1) then
        match rel.operator
        case LESS(__) then
          let &preExp += '<%res%> = Less(<%e1%>,<%e2%>);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%res%> = LessEq(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%res%> = Greater(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%res%> = GreaterEq(<%e1%>,<%e2%>);<%\n%>'
          res
        end match
      else
        let isReal = if isRealType(typeof(rel.exp1)) then (if isRealType(typeof(rel.exp2)) then 'true' else '') else ''
        match rel.operator
        case LESS(__) then
          let hysteresisfunction = if isReal then 'LessZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'Less(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case LESSEQ(__) then
          let hysteresisfunction = if isReal then 'LessEqZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'LessEq(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case GREATER(__) then
          let hysteresisfunction = if isReal then 'GreaterZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'Greater(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case GREATEREQ(__) then
          let hysteresisfunction = if isReal then 'GreaterEqZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'GreaterEq(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        end match
    case SOME((exp,i,j)) then
      let e1 = daeExp(rel.exp1, context, &preExp, &varDecls, &auxFunction)
      let e2 = daeExp(rel.exp2, context, &preExp, &varDecls, &auxFunction)
      let res = tempDecl("modelica_boolean", &varDecls)
      if intEq(rel.index,-1) then
        match rel.operator
        case LESS(__) then
          let &preExp += '<%res%> = Less(<%e1%>,<%e2%>);<%\n%>'
          res
        case LESSEQ(__) then
          let &preExp += '<%res%> = LessEq(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATER(__) then
          let &preExp += '<%res%> = Greater(<%e1%>,<%e2%>);<%\n%>'
          res
        case GREATEREQ(__) then
          let &preExp += '<%res%> = GreaterEq(<%e1%>,<%e2%>);<%\n%>'
          res
        end match
      else
        let isReal = if isRealType(typeof(rel.exp1)) then (if isRealType(typeof(rel.exp2)) then 'true' else '') else ''
        match rel.operator
        case LESS(__) then
          let hysteresisfunction = if isReal then 'LessZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'Less(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case LESSEQ(__) then
          let hysteresisfunction = if isReal then 'LessEqZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'LessEq(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case GREATER(__) then
          let hysteresisfunction = if isReal then 'GreaterZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'Greater(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        case GREATEREQ(__) then
          let hysteresisfunction = if isReal then 'GreaterEqZC(<%e1%>, <%e2%>, data->simulationInfo.storedRelations[<%rel.index%>])' else 'GreaterEq(<%e1%>,<%e2%>)'
          let &preExp += '<%res%> = <%hysteresisfunction%>;<%\n%>'
          res
        end match
    end match
  end match
end match
end daeExpRelationSim;

template daeExpIf(Exp exp, Context context, Text &preExp,
                  Text &varDecls, Text &auxFunction)
 "Generates code for an if expression."
::=
match exp
case IFEXP(__) then
  let condExp = daeExp(expCond, context, &preExp, &varDecls, &auxFunction)
  let &preExpThen = buffer ""
  let eThen = daeExp(expThen, context, &preExpThen, &varDecls, &auxFunction)
  let &preExpElse = buffer ""
  let eElse = daeExp(expElse, context, &preExpElse, &varDecls, &auxFunction)
  let shortIfExp = if preExpThen then "" else if preExpElse then "" else if isArrayType(typeof(exp)) then "" else "x"
  (if shortIfExp
    then
      // Safe to do if eThen and eElse don't emit pre-expressions
      '(<%condExp%>?<%eThen%>:<%eElse%>)'
    else
      let condVar = tempDecl("modelica_boolean", &varDecls)
      let resVar = tempDeclTuple(typeof(exp), &varDecls)
      let &preExp +=
      <<
      <%condVar%> = (modelica_boolean)<%condExp%>;
      if(<%condVar%>)
      {
        <%preExpThen%>
        <%if eThen then resultVarAssignment(typeof(exp),resVar,eThen)%>
      }
      else
      {
        <%preExpElse%>
        <%if eElse then resultVarAssignment(typeof(exp),resVar,eElse)%>
      }<%\n%>
      >>
      resVar)
end daeExpIf;

template daeExpSum(Exp exp, Context context, Text &preExp,
                  Text &varDecls, Text &auxFunction)
 "Generates code for an if expression."
::=
match exp
case SUM(__) then
  let start = printExpStr(startIt)
  let &anotherPre = buffer ""
  let stop = printExpStr(endIt)
  let bodyStr = daeExpIteratedCref(body)
  let summationVar = <<sum>>
  let iterVar = printExpStr(iterator)
  let &preExp +=<<

  modelica_integer  $P<%iterVar%> = 0; // the iterator
  modelica_real <%summationVar%> = 0.0; //the sum
  for($P<%iterVar%> = <%start%>; $P<%iterVar%> < <%stop%>; $P<%iterVar%>++)
  {
    <%summationVar%> += <%bodyStr%>($P<%iterVar%>);
  }

  >>
  summationVar
end daeExpSum;

template daeExpIteratedCref(Exp exp)
::=
match exp
case (CREF(__)) then
  let subs = (crefSubs(componentRef) |> sub => subscriptToCStr(sub) ; separator=",")
  <<<%iteratedCrefStr(componentRef)%>_index>>
end daeExpIteratedCref;

template iteratedCrefStr(ComponentRef cref)
::=
match cref
case (CREF_IDENT(__)) then
    <<$P<%ident%>>>
case (CREF_QUAL(__)) then
    <<$P<%ident%><%iteratedCrefStr(componentRef)%>>>
end iteratedCrefStr;

template resultVarAssignment(DAE.Type ty, Text lhs, Text rhs) "Tuple need to be considered"
::=
match ty
case T_TUPLE(__) then
  (types |> t hasindex i1 fromindex 1 => '<%lhs%>.c<%i1%> = <%rhs%>.c<%i1%>;' ; separator="\n")
else
  '<%lhs%> = <%rhs%>;'
end resultVarAssignment;

template daeExpRecord(Exp rec, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match rec
  case RECORD(__) then
  let name = tempDecl(underscorePath(path), &varDecls)
  let ass = threadTuple(exps,comp) |>  (exp,compn) => '<%name%>._<%compn%> = <%daeExp(exp, context, &preExp, &varDecls, &auxFunction)%>;<%\n%>'
  let &preExp += ass
  name
end daeExpRecord;

template daeExpPartEvalFunction(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match exp
    case PARTEVALFUNCTION(ty=T_FUNCTION_REFERENCE_VAR(functionType = t as T_FUNCTION(__)),origType=T_FUNCTION_REFERENCE_VAR(functionType = orig as T_FUNCTION(functionAttributes=attr as FUNCTION_ATTRIBUTES(__), source={name}))) then
      let &varDeclInner = buffer ""
      let &ret = buffer ""
      let retInput = match t.funcResultType
        case T_TUPLE(types=_::tys) then
          (tys |> ty =>
            let name = 'tmp<%System.tmpTick()%>'
            let &ret += ', <%name%>'
            ', <%expTypeArrayIf(ty)%> <%name%>')
      let func = 'closure<%System.tmpTickIndex(2/*auxFunction*/)%>_<%underscorePath(name)%>'
      let return = match t.funcResultType case T_NORETCALL(__) then "" else "return "
      let closure = tempDecl("modelica_metatype",&varDecls)
      let createClosure = (expList |> e => ', <%daeExp(e,context,&preExp,&varDecls,&auxFunction)%>') + (if attr.isFunctionPointer then ', _<%underscorePath(name)%>')
      let &preExp += '<%closure%> = mmc_mk_box<%if attr.isFunctionPointer then daeExpMetaHelperBoxStart(incrementInt(listLength(expList),1)) else daeExpMetaHelperBoxStart(listLength(expList))%>0<%createClosure%>);<%\n%>'
      let &auxFunction +=
      <<
      static <%match t.funcResultType case T_NORETCALL(__) then "void" else "modelica_metatype"%> <%func%>(threadData_t *thData, modelica_metatype closure<%t.funcArg |> a as FUNCARG(__) => ', <%expTypeArrayIf(a.ty)%> <%a.name%>'%><%retInput%>)
      {
        <%varDeclInner%>
        <%setDifference(orig.funcArg,t.funcArg) |> a as FUNCARG(__) hasindex i1 fromindex 1 => '<%expTypeArrayIf(a.ty)%> <%a.name%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(closure),<%i1%>));<%\n%>'%>
        <%
        if attr.isFunctionPointer then
          let fname = '_<%underscorePath(name)%>'
          let func = '(MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%fname%>), 1)))'
          let typeCast1 = generateTypeCastFromType(orig, true)
          let typeCast2 = generateTypeCastFromType(orig, false)
          <<
          modelica_fnptr <%fname%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(closure),<%incrementInt(listLength(setDifference(orig.funcArg,t.funcArg)),1)%>));
          if (MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%fname%>),2))) {
            <%return%> (<%typeCast1%> <%func%>) (thData, MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%fname%>),2))<%orig.funcArg |> a as FUNCARG(__) => ', <%a.name%>'%><%ret%>);
          } else { /* No closure in the called variable */
            <%return%> (<%typeCast2%> <%func%>) (thData<%orig.funcArg |> a as FUNCARG(__) => ', <%a.name%>'%><%ret%>);
          }
          >>
        else
          '<%return%>boxptr_<%underscorePath(name)%>(thData<%orig.funcArg |> a as FUNCARG(__) => ', <%a.name%>'%><%ret%>);'
        %>
      }
      >>
      '(modelica_fnptr) mmc_mk_box2(0,<%func%>,<%closure%>)'
      // error(sourceInfo(), 'PARTEVALFUNCTION: <%ExpressionDump.printExpStr(exp)%>, ty=<%unparseType(ty)%>, origType=<%unparseType(origType)%>')
    case PARTEVALFUNCTION(__) then
      error(sourceInfo(), 'PARTEVALFUNCTION: <%ExpressionDump.printExpStr(exp)%>, ty=<%unparseType(ty)%>, origType=<%unparseType(origType)%>')
end daeExpPartEvalFunction;

template daeExpCall(Exp call, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a function call."
::=
  match call
  // special builtins
  case CALL(path=IDENT(name="smooth"),
            expLst={e1, e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    '<%var2%>'

  case CALL(path=IDENT(name="DIVISION"),
            expLst={e1, e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    let var3 = Util.escapeModelicaStringToCString(printExpStr(e2))
    (match context
      case FUNCTION_CONTEXT(__) then
        'DIVISION(<%var1%>,<%var2%>,"<%var3%>")'
      else
        'DIVISION_SIM(<%var1%>,<%var2%>,"<%var3%>",equationIndexes)'
    )

  case CALL(attr=CALL_ATTR(ty=ty),
            path=IDENT(name="DIVISION_ARRAY_SCALAR"),
            expLst={e1, e2}) then
    let type = match ty case T_ARRAY(ty=T_INTEGER(__)) then "integer_array"
                        case T_ARRAY(ty=T_ENUMERATION(__)) then "integer_array"
                        else "real_array"
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    let var3 = Util.escapeModelicaStringToCString(printExpStr(e2))
    'division_alloc_<%type%>_scalar(threadData,<%var1%>,<%var2%>,"<%var3%>")'

  case exp as CALL(attr=CALL_ATTR(ty=ty), path=IDENT(name="DIVISION_ARRAY_SCALAR")) then
    error(sourceInfo(),'Code generation does not support <%printExpStr(exp)%>')

  case CALL(path=IDENT(name="der"), expLst={arg as CREF(__)}) then
    '$P$DER<%cref(arg.componentRef)%>'
  case CALL(path=IDENT(name="der"), expLst={exp}) then
    error(sourceInfo(), 'Code generation does not support der(<%printExpStr(exp)%>)')
  case CALL(path=IDENT(name="pre"), expLst={arg}) then
    daeExpCallPre(arg, context, preExp, varDecls, &auxFunction)
  // a $_start is used to get get start value of a variable
  case CALL(path=IDENT(name="$_start"), expLst={arg}) then
    daeExpCallStart(arg, context, preExp, varDecls, &auxFunction)
  // a $_initialGuess is used to get initial guess for nonlinear solver
  case CALL(path=IDENT(name="$_initialGuess"), expLst={arg as CREF(__)}) then
    let namestr = cref(arg.componentRef)
    '( <%namestr%>)' //
  case CALL(path=IDENT(name="$_old"), expLst={arg as CREF(__)}) then
    let namestr = cref(arg.componentRef)
    '( _<%namestr%>(1))' //
  // if arg >= 0 then 1 else -1
  case CALL(path=IDENT(name="$_signNoNull"), expLst={e1}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    '(<%var1%> >= 0.0 ? 1.0:-1.0)'
  // numerical der()
  case CALL(path=IDENT(name="$_DF$DER"), expLst={arg as CREF(__)}) then
    let namestr = cref(arg.componentRef)
    '($P<%BackendDAE.symEulerDT%> == 0.0 ? $P$DER<%namestr%> : (<%namestr%> - _<%namestr%>(1))/$P<%BackendDAE.symEulerDT%>)'
  // round
  case CALL(path=IDENT(name="$_round"), expLst={e1}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    '((modelica_integer)round((modelica_real)<%var1%>))'
  case CALL(path=IDENT(name="edge"), expLst={arg as CREF(__)}) then
    '(<%cref(arg.componentRef)%> && !$P$PRE<%cref(arg.componentRef)%>)'
  case CALL(path=IDENT(name="edge"), expLst={LUNARY(exp = arg as CREF(__))}) then
    '(!<%cref(arg.componentRef)%> && $P$PRE<%cref(arg.componentRef)%>)'
  case CALL(path=IDENT(name="edge"), expLst={exp}) then
    error(sourceInfo(), 'Code generation does not support edge(<%printExpStr(exp)%>)')
  case CALL(path=IDENT(name="change"), expLst={arg as CREF(__)}) then
    '(<%cref(arg.componentRef)%> != $P$PRE<%cref(arg.componentRef)%>)'
  case CALL(path=IDENT(name="change"), expLst={exp}) then
    error(sourceInfo(), 'Code generation does not support change(<%printExpStr(exp)%>)')
  case CALL(path=IDENT(name="cardinality"), expLst={exp}) then
    error(sourceInfo(), 'Code generation does not support cardinality(<%printExpStr(exp)%>). It should have been handled somewhere else in the compiler.')

  case CALL(path=IDENT(name="print"), expLst={e1}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    'fputs(MMC_STRINGDATA(<%var1%>),stdout)'

  case CALL(path=IDENT(name="max"), attr=CALL_ATTR(ty = T_REAL(__)), expLst={e1,e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    'fmax(<%var1%>,<%var2%>)'

  case CALL(path=IDENT(name="max"), expLst={e1,e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    'modelica_integer_max((modelica_integer)<%var1%>,(modelica_integer)<%var2%>)'

  case CALL(path=IDENT(name="sum"), attr=CALL_ATTR(ty = ty), expLst={e}) then
    let arr = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    let ty_str = '<%expTypeArray(ty)%>'
    'sum_<%ty_str%>(<%arr%>)'

  case CALL(path=IDENT(name="min"), attr=CALL_ATTR(ty = T_REAL(__)), expLst={e1,e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    'fmin(<%var1%>,<%var2%>)'

  case CALL(path=IDENT(name="min"), expLst={e1,e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    'modelica_integer_min((modelica_integer)<%var1%>,(modelica_integer)<%var2%>)'

  case CALL(path=IDENT(name="abs"), expLst={e1}, attr=CALL_ATTR(ty = T_INTEGER(__))) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    'labs(<%var1%>)'

  case CALL(path=IDENT(name="abs"), expLst={e1}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    'fabs(<%var1%>)'

  case CALL(path=IDENT(name="sqrt"), expLst={e1}, attr=attr as CALL_ATTR(__)) then
    let argStr = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    (if isPositiveOrZero(e1)
     then
       'sqrt(<%argStr%>)'
     else
       let tmp = tempDecl(expTypeFromExpModelica(e1),&varDecls)
       let ass = '(<%tmp%> >= 0.0)'
       let &preExpMsg = buffer ""
       let retPre = assertCommonVar(ass,'"Model error: Argument of sqrt(<%Util.escapeModelicaStringToCString(printExpStr(e1))%>) was %g should be >= 0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
       let &preExp += '<%tmp%> = <%argStr%>; <%\n%><%retPre%>'
       'sqrt(<%tmp%>)')

  case CALL(path=IDENT(name="log"), expLst={e1}, attr=attr as CALL_ATTR(__)) then
    let argStr = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl(expTypeFromExpModelica(e1),&varDecls)
    let ass = '(<%tmp%> > 0.0)'
    let &preExpMsg = buffer ""
    let retPre = assertCommonVar(ass,'"Model error: Argument of log(<%Util.escapeModelicaStringToCString(printExpStr(e1))%>) was %g should be > 0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
    let &preExp += '<%tmp%> = <%argStr%>;<%retPre%>'
    'log(<%tmp%>)'

  case CALL(path=IDENT(name="log10"), expLst={e1}, attr=attr as CALL_ATTR(__)) then
    let argStr = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl(expTypeFromExpModelica(e1),&varDecls)
    let ass = '(<%tmp%> > 0.0)'
    let &preExpMsg = buffer ""
    let retPre = assertCommonVar(ass,'"Model error: Argument of log10(<%Util.escapeModelicaStringToCString(printExpStr(e1))%>) was %g should be > 0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
    let &preExp += '<%tmp%> = <%argStr%>;<%retPre%>'
    'log10(<%tmp%>)'

  case CALL(path=IDENT(name="acos"), expLst={e1}, attr=attr as CALL_ATTR(__)) then
    let argStr = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl("modelica_real",&varDecls)
    let ass = '(<%tmp%> >= -1.0 && <%tmp%> <= 1.0)'
    let &preExpMsg = buffer ""
    let retPre = assertCommonVar(ass,'"Model error: Argument of <%Util.escapeModelicaStringToCString(printExpStr(call))%> outside the domain -1.0 <= %g <= 1.0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
    let &preExp += '<%tmp%> = <%argStr%>;<%retPre%>'
    'acos(<%tmp%>)'

  case CALL(path=IDENT(name="asin"), expLst={e1}, attr=attr as CALL_ATTR(__)) then
    let argStr = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl("modelica_real",&varDecls)
    let ass = '(<%tmp%> >= -1.0 && <%tmp%> <= 1.0)'
    let &preExpMsg = buffer ""
    let retPre = assertCommonVar(ass,'"Model error: Argument of <%Util.escapeModelicaStringToCString(printExpStr(call))%> outside the domain -1.0 <= %g <= 1.0", <%tmp%>', context, &preExpMsg, &varDecls, dummyInfo)
    let &preExp += '<%tmp%> = <%argStr%>;<%retPre%>'
    'asin(<%tmp%>)'

  /* Begin code generation of event triggering math functions */

  case CALL(path=IDENT(name="div"), expLst={e1,e2, index}, attr=CALL_ATTR(ty = ty)) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    let constIndex = daeExp(index, context, &preExp, &varDecls, &auxFunction)
    '_event_div_<%expTypeShort(ty)%>(<%var1%>, <%var2%>, <%constIndex%>, data)'

  case CALL(path=IDENT(name="integer"), expLst={inExp,index}) then
    let exp = daeExp(inExp, context, &preExp, &varDecls, &auxFunction)
    let constIndex = daeExp(index, context, &preExp, &varDecls, &auxFunction)
    '(_event_integer(<%exp%>, <%constIndex%>, data))'

  case CALL(path=IDENT(name="floor"), expLst={inExp,index}, attr=CALL_ATTR(ty = ty)) then
    let exp = daeExp(inExp, context, &preExp, &varDecls, &auxFunction)
    let constIndex = daeExp(index, context, &preExp, &varDecls, &auxFunction)
    '((modelica_<%expTypeShort(ty)%>)_event_floor(<%exp%>, <%constIndex%>, data))'

  case CALL(path=IDENT(name="ceil"), expLst={inExp,index}, attr=CALL_ATTR(ty = ty)) then
    let exp = daeExp(inExp, context, &preExp, &varDecls, &auxFunction)
    let constIndex = daeExp(index, context, &preExp, &varDecls, &auxFunction)
    '((modelica_<%expTypeShort(ty)%>)_event_ceil(<%exp%>, <%constIndex%>, data))'

  /* end codegeneration of event triggering math functions */

  case CALL(path=IDENT(name="integer"), expLst={inExp}) then
    let exp = daeExp(inExp, context, &preExp, &varDecls, &auxFunction)
    '((modelica_integer)floor(<%exp%>))'

  case CALL(path=IDENT(name="div"), expLst={e1,e2}, attr=CALL_ATTR(ty = T_INTEGER(__))) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    let tvar = tempDecl("modelica_integer", &varDecls)
    let &preExp += '<%tvar%> = <%var2%>;<%\n%>'
    let &preExp +=
      if acceptMetaModelicaGrammar()
        then 'if (<%tvar%> == 0) {<%generateThrow()%>;}<%\n%>'
        else 'if (<%tvar%> == 0) {throwStreamPrint(threadData, "Division by zero %s", "<%Util.escapeModelicaStringToCString(printExpStr(call))%>");}<%\n%>'
    'ldiv(<%var1%>,<%tvar%>).quot'

  case CALL(path=IDENT(name="div"), expLst={e1,e2}) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    let tvar = tempDecl("modelica_real", &varDecls)
    let &preExp += '<%tvar%> = <%var2%>;<%\n%>'
    let &preExp +=
      if acceptMetaModelicaGrammar()
        then 'if (<%tvar%> == 0.0) {<%generateThrow()%>;}<%\n%>'
        else 'if (<%tvar%> == 0.0) {throwStreamPrint(threadData, "Division by zero %s", "<%Util.escapeModelicaStringToCString(printExpStr(call))%>");}<%\n%>'
    'trunc(<%var1%>/<%var2%>)'

  case CALL(path=IDENT(name="mod"), expLst={e1,e2}, attr=CALL_ATTR(ty = ty)) then
    let var1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(e2, context, &preExp, &varDecls, &auxFunction)
    'modelica_mod_<%expTypeShort(ty)%>(<%var1%>,<%var2%>)'

  case CALL(path=IDENT(name="max"), attr=CALL_ATTR(ty = ty), expLst={array}) then
    let expVar = daeExp(array, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeArray(ty)%>'
    let tvar = tempDecl(expTypeModelica(ty), &varDecls)
    let &preExp += '<%tvar%> = max_<%arr_tp_str%>(<%expVar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="min"), attr=CALL_ATTR(ty = ty), expLst={array}) then
    let expVar = daeExp(array, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeArray(ty)%>'
    let tvar = tempDecl(expTypeModelica(ty), &varDecls)
    let &preExp += '<%tvar%> = min_<%arr_tp_str%>(<%expVar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="fill"), expLst=val::dims, attr=CALL_ATTR(ty = ty)) then
    let valExp = daeExp(val, context, &preExp, &varDecls, &auxFunction)
    let dimsExp = (dims |> dim =>
      daeExp(dim, context, &preExp, &varDecls, &auxFunction) ;separator=", ")
    let ty_str = '<%expTypeArray(ty)%>'
    let tvar = tempDecl(ty_str, &varDecls)
    let &preExp += 'fill_alloc_<%ty_str%>(&<%tvar%>, <%valExp%>, <%listLength(dims)%>, <%dimsExp%>);<%\n%>'
    '<%tvar%>'

  case call as CALL(path=IDENT(name="vector")) then
    error(sourceInfo(),'vector() call does not have a C implementation <%printExpStr(call)%>')

  case CALL(path=IDENT(name="cat"), expLst=dim::arrays, attr=CALL_ATTR(ty = ty)) then
    let dim_exp = daeExp(dim, context, &preExp, &varDecls, &auxFunction)
    let arrays_exp = (arrays |> array =>
      daeExp(array, context, &preExp, &varDecls, &auxFunction) ;separator=", &")
    let ty_str = '<%expTypeArray(ty)%>'
    let tvar = tempDecl(ty_str, &varDecls)
    let &preExp += 'cat_alloc_<%ty_str%>(<%dim_exp%>, &<%tvar%>, <%listLength(arrays)%>, &<%arrays_exp%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="promote"), expLst={A, n}) then
    let var1 = daeExp(A, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(n, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeFromExpArray(A)%>'
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'promote_alloc_<%arr_tp_str%>(&<%var1%>, <%var2%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="transpose"), expLst={A}) then
    let var1 = daeExp(A, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeFromExpArray(A)%>'
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'transpose_alloc_<%arr_tp_str%>(&<%var1%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="symmetric"), expLst={A}) then
    let var1 = daeExp(A, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeFromExpArray(A)%>'
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'symmetric_<%arr_tp_str%>(&<%var1%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="skew"), expLst={A}) then
    let var1 = daeExp(A, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = '<%expTypeFromExpArray(A)%>'
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'skew_<%arr_tp_str%>(&<%var1%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="cross"), expLst={v1, v2}) then
    let var1 = daeExp(v1, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(v2, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = expTypeFromExpArray(v1)
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'cross_alloc_<%arr_tp_str%>(&<%var1%>, &<%var2%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="identity"), expLst={A}) then
    let var1 = daeExp(A, context, &preExp, &varDecls, &auxFunction)
    let arr_tp_str = expTypeFromExpArray(A)
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let &preExp += 'identity_alloc_<%arr_tp_str%>(<%var1%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="diagonal"), expLst={A as ARRAY(__)}) then
    let arr_tp_str = expTypeFromExpArray(A)
    let tvar = tempDecl(arr_tp_str, &varDecls)
    let params = (A.array |> e =>
      '<%daeExp(e, context, &preExp, &varDecls, &auxFunction)%>'
    ;separator=", ")
    let &preExp += 'diagonal_alloc_<%arr_tp_str%>(&<%tvar%>, <%listLength(A.array)%>, <%params%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="String"), expLst={s, format}) then
    let tvar = tempDecl("modelica_string", &varDecls)
    let sExp = daeExp(s, context, &preExp, &varDecls, &auxFunction)

    let formatExp = daeExp(format, context, &preExp, &varDecls, &auxFunction)
    let typeStr = expTypeFromExpModelica(s)
    let &preExp += '<%tvar%> = <%typeStr%>_to_modelica_string_format(<%sExp%>, <%formatExp%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="String"), expLst={s, minlen, leftjust}) then
    let tvar = tempDecl("modelica_string", &varDecls)
    let sExp = daeExp(s, context, &preExp, &varDecls, &auxFunction)
    let minlenExp = daeExp(minlen, context, &preExp, &varDecls, &auxFunction)
    let leftjustExp = daeExp(leftjust, context, &preExp, &varDecls, &auxFunction)
    let typeStr = expTypeFromExpModelica(s)
    match typeStr
    case "modelica_real" then
      let &preExp += '<%tvar%> = <%typeStr%>_to_modelica_string(<%sExp%>, <%minlenExp%>, <%leftjustExp%>, 6);<%\n%>'
      '<%tvar%>'
    else
    let &preExp += '<%tvar%> = <%typeStr%>_to_modelica_string(<%sExp%>, <%minlenExp%>, <%leftjustExp%>);<%\n%>'
    '<%tvar%>'
    end match

  case CALL(path=IDENT(name="String"), expLst={s, minlen, leftjust, signdig}) then
    let tvar = tempDecl("modelica_string", &varDecls)
    let sExp = daeExp(s, context, &preExp, &varDecls, &auxFunction)
    let minlenExp = daeExp(minlen, context, &preExp, &varDecls, &auxFunction)
    let leftjustExp = daeExp(leftjust, context, &preExp, &varDecls, &auxFunction)
    let signdigExp = daeExp(signdig, context, &preExp, &varDecls, &auxFunction)
    let &preExp += '<%tvar%> = modelica_real_to_modelica_string(<%sExp%>, <%minlenExp%>, <%leftjustExp%>, <%signdigExp%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="delay"), expLst={ICONST(integer=index), e, d, delayMax}) then
    let tvar = tempDecl("modelica_real", &varDecls)

    let var1 = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    let var2 = daeExp(d, context, &preExp, &varDecls, &auxFunction)
    let var3 = daeExp(delayMax, context, &preExp, &varDecls, &auxFunction)
    let &preExp += '<%tvar%> = delayImpl(data, <%index%>, <%var1%>, time, <%var2%>, <%var3%>);<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name="Integer"), expLst={toBeCasted}) then
    let castedVar = daeExp(toBeCasted, context, &preExp, &varDecls, &auxFunction)
    '((modelica_integer)<%castedVar%>)'

  case CALL(path=IDENT(name="clock"), expLst={}) then
    'mmc_clock()'

  case CALL(path=IDENT(name="noEvent"), expLst={e1}) then
    daeExp(e1, context, &preExp, &varDecls, &auxFunction)

  case CALL(path=IDENT(name="$getPart"), expLst={e1}) then
    daeExp(e1, context, &preExp, &varDecls, &auxFunction)

  case CALL(path=IDENT(name="sample"), expLst={ICONST(integer=index), _, _}) then
    '$P$sample<%index%>'

  case CALL(path=IDENT(name="anyString"), expLst={e1}) then
    'mmc_anyString(<%daeExp(e1, context, &preExp, &varDecls, &auxFunction)%>)'

  case CALL(path=IDENT(name="fail"), attr = CALL_ATTR(builtin = true)) then
    '<%generateThrow()%>'

  case CALL(path=IDENT(name="mmc_get_field"), expLst={s1, ICONST(integer=i)}) then
    let tvar = tempDecl("modelica_metatype", &varDecls)
    let expPart = daeExp(s1, context, &preExp, &varDecls, &auxFunction)
    let &preExp += '<%tvar%> = MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%expPart%>), <%i%>));<%\n%>'
    '<%tvar%>'

  case CALL(path=IDENT(name = "mmc_unbox_record"), expLst={s1}, attr=CALL_ATTR(ty=ty)) then
    let argStr = daeExp(s1, context, &preExp, &varDecls, &auxFunction)
    unboxRecord(argStr, ty, &preExp, &varDecls)

  case CALL(path=IDENT(name = "threadData")) then
    "threadData"

  case CALL(path=IDENT(name = "intBitNot"),expLst={e}) then
    let e1 = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    '(~<%e1%>)'

  case CALL(path=IDENT(name = name as "intBitNot"),expLst={e1,e2})
  case CALL(path=IDENT(name = name as "intBitAnd"),expLst={e1,e2})
  case CALL(path=IDENT(name = name as "intBitOr"),expLst={e1,e2})
  case CALL(path=IDENT(name = name as "intBitXor"),expLst={e1,e2})
  case CALL(path=IDENT(name = name as "intBitLShift"),expLst={e1,e2})
  case CALL(path=IDENT(name = name as "intBitRShift"),expLst={e1,e2}) then
    let i1 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let i2 = daeExp(e1, context, &preExp, &varDecls, &auxFunction)
    let op = (match name
      case "intBitAnd" then "&"
      case "intBitOr" then "|"
      case "intBitXor" then "^"
      case "intBitLShift" then "<<"
      case "intBitRShift" then ">>")
    '((<%i1%>) <%op%> (<%i2%>))'

  case exp as CALL(attr=attr as CALL_ATTR(tailCall=tail as TAIL(__))) then
    let &postExp = buffer ""
    let tail = daeExpTailCall(expLst, tail.vars, context, &preExp, &postExp, &varDecls, &auxFunction)
    let res = <<
    /* Tail recursive call */
    <%tail%><%&postExp%>goto _tailrecursive;
    /* TODO: Make sure any eventual dead code below is never generated */
    >>
    let &preExp += res
    ""

  case exp as CALL(attr=attr as CALL_ATTR(__)) then
    let additionalOutputs = (match attr.ty
      case T_TUPLE(types=t::ts) then List.fill(", NULL",listLength(ts)))
    let res = daeExpCallTuple(exp, additionalOutputs, context, &preExp, &varDecls, &auxFunction)
    match context
      case FUNCTION_CONTEXT(__) then res
      case PARALLEL_FUNCTION_CONTEXT(__) then res
      else
        if boolAnd(profileFunctions(),boolNot(attr.builtin)) then
          let funName = '<%underscorePath(exp.path)%>'
          let tvar = match attr.ty
            case T_NORETCALL(__) then
              ""
            case T_TUPLE(types=t::_)
            case t
            then
              let tvar2 = tempDecl(expTypeArrayIf(t),&varDecls)
              let &preExp += if isArrayType(t) then '<%tvar2%>.dim_size = 0;<%\n%>'
              tvar2
          let &preExp += 'SIM_PROF_TICK_FN(<%funName%>_index);<%\n%>'
          let &preExp += if tvar then '<%tvar%> = <%res%>;<%\n%>' else '<%res%>;<%\n%>'
          let &preExp += 'SIM_PROF_ACC_FN(<%funName%>_index);<%\n%>'
          tvar
        else res
end daeExpCall;

template daeExpCallTuple(Exp call, Text additionalOutputs /* arguments 2..N */, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  match call
  case exp as CALL(attr=attr as CALL_ATTR(__)) then
    let argStr = if boolOr(attr.builtin,isParallelFunctionContext(context))
                   then (expLst |> exp => '<%daeExp(exp, context, &preExp, &varDecls, &auxFunction)%>' ;separator=", ")
                 else ("threadData" + (expLst |> exp => (", " + daeExp(exp, context, &preExp, &varDecls, &auxFunction))))
    if attr.isFunctionPointerCall
      then
        let typeCast1 = generateTypeCast(attr.ty, expLst, true)
        let typeCast2 = generateTypeCast(attr.ty, expLst, false)
        let name = '_<%underscorePath(path)%>'
        let func = '(MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%name%>), 1)))'
        let closure = '(MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%name%>), 2)))'
        let argStrPointer = ('threadData, <%closure%>' + (expLst |> exp => (", " + daeExp(exp, context, &preExp, &varDecls, &auxFunction))))
        //'<%name%>(<%argStr%><%additionalOutputs%>)'
        '<%closure%> ? (<%typeCast1%> <%func%>) (<%argStrPointer%><%additionalOutputs%>) : (<%typeCast2%> <%func%>) (<%argStr%><%additionalOutputs%>)'
      else
        let name = '<% if attr.builtin then "" else "omc_" %><%underscorePath(path)%>'
        '<%name%>(<%argStr%><%additionalOutputs%>)'
end daeExpCallTuple;

template generateTypeCast(Type ty, list<DAE.Exp> es, Boolean isClosure)
::=
  let ret = (match ty
    case T_NORETCALL(__) then "void"
    else "modelica_metatype")
  let inputs = es |> e => ', <%expTypeFromExpArrayIf(e)%>'
  let outputs = match ty
    case T_TUPLE(types=_::tys) then (tys |> t => ', <%expTypeArrayIf(t)%>')
  '(<%ret%>(*)(threadData_t*<%if isClosure then ", modelica_metatype"%><%inputs%><%outputs%>))'
end generateTypeCast;

template generateTypeCastFromType(Type ty, Boolean isClosure)
::=
  let ret = (match ty
    case T_FUNCTION(funcResultType=T_NORETCALL(__)) then "void"
    else "modelica_metatype")
  let inputs = match ty
    case T_FUNCTION(__) then
      (funcArg |> fa as FUNCARG(__) => ', <%expTypeArrayIf(fa.ty)%>')
  let outputs = match ty
    case T_FUNCTION(funcResultType=T_TUPLE(types=_::tys)) then (tys |> t => ', <%expTypeArrayIf(t)%>')
  '(<%ret%>(*)(threadData_t*<%if isClosure then ", modelica_metatype"%><%inputs%><%outputs%>))'
end generateTypeCastFromType;

template daeExpTailCall(list<DAE.Exp> es, list<String> vs, Context context, Text &preExp, Text &postExp, Text &varDecls, Text &auxFunction)
::=
  match es
  case e::erest then
    match vs
    case v::vrest then
      let exp = daeExp(e,context,&preExp,&varDecls, &auxFunction)
      match e
      case CREF(componentRef = cr, ty = T_FUNCTION_REFERENCE_VAR(__)) then
        // adrpo: ignore _x = _x!
        if stringEq(v, crefStr(cr))
        then '<%daeExpTailCall(erest, vrest, context, &preExp, &postExp, &varDecls, &auxFunction)%>'
        else '_<%v%> = <%exp%>;<%\n%><%daeExpTailCall(erest, vrest, context, &preExp, &postExp, &varDecls, &auxFunction)%>'
      case _ then
        (if anyExpHasCrefName(erest, v) then
          /* We might overwrite a value with something else, so make an extra copy of it */
          let tmp = tempDecl(expTypeFromExpModelica(e),&varDecls)
          let &postExp += '_<%v%> = <%tmp%>;<%\n%>'
          '<%tmp%> = <%exp%>;<%\n%><%daeExpTailCall(erest, vrest, context, &preExp, &postExp, &varDecls, &auxFunction)%>'
        else
          let restText = daeExpTailCall(erest, vrest, context, &preExp, &postExp, &varDecls, &auxFunction)
          let v2 = '_<%v%>'
          if stringEq(v2, exp)
            then restText
            else '<%v2%> = <%exp%>;<%\n%><%restText%>')
end daeExpTailCall;

template daeExpArray(Exp exp, Context context, Text &preExp,
                     Text &varDecls, Text &auxFunction)
 "Generates code for an array expression."
::=
match exp
case ARRAY(array = array, scalar = scalar, ty = T_ARRAY(ty = t as T_COMPLEX(__))) then
  let arrayTypeStr = expTypeArray(ty)
  let arrayVar = tempDecl(arrayTypeStr, &varDecls)
  let rec_name = expTypeShort(t)
  let &preExp += '<%\n%>alloc_generic_array(&<%arrayVar%>, sizeof(<%rec_name%>), 1, <%listLength(array)%>);<%\n%>'
  let params = (array |> e hasindex i1 fromindex 1 =>
      let prefix = if scalar then '(<%expTypeFromExpModelica(e)%>)' else '&'
      '(*((<%rec_name%>*)generic_array_element_addr(&<%arrayVar%>, sizeof(<%rec_name%>), 1, <%i1%>))) = <%prefix%><%daeExp(e, context, &preExp, &varDecls, &auxFunction)%>;'
      ;separator="\n")
  let &preExp += '<%params%><%\n%>'
  arrayVar
case ARRAY(array={}) then
  let arrayVar = tempDecl("base_array_t", &varDecls)
  let &preExp += 'simple_alloc_1d_base_array(&<%arrayVar%>, 0, NULL);<%\n%>'
  arrayVar
case ARRAY(__) then
  let arrayTypeStr = expTypeArray(ty)
  let arrayVar = tempDecl(arrayTypeStr, &varDecls)
  let scalarPrefix = if scalar then "scalar_" else ""
  let scalarRef = if scalar then "&" else ""
  let params = (array |> e =>
      let prefix = if scalar then '(<%expTypeFromExpModelica(e)%>)' else ""
      '<%prefix%><%daeExp(e, context, &preExp, &varDecls, &auxFunction)%>'
    ;separator=", ")
  let &preExp += 'array_alloc_<%scalarPrefix%><%arrayTypeStr%>(&<%arrayVar%>, <%listLength(array)%><%if params then ", "%><%params%>);<%\n%>'
  arrayVar
end daeExpArray;


template daeExpMatrix(Exp exp, Context context, Text &preExp,
                      Text &varDecls, Text &auxFunction)
 "Generates code for a matrix expression."
::=
  match exp
  case MATRIX(matrix={{}})  // special case for empty matrix: create dimensional array Real[0,1]
  case MATRIX(matrix={})    // special case for empty array: create dimensional array Real[0,1]
    then
    let arrayTypeStr = expTypeArray(ty)
    let tmp = tempDecl(arrayTypeStr, &varDecls)
    let &preExp += 'alloc_<%arrayTypeStr%>(&<%tmp%>, 2, 0, 1);<%\n%>'
    tmp
  case m as MATRIX(__) then
    let typeStr = expTypeShort(m.ty)
    let arrayTypeStr = expTypeArray(m.ty)
    match typeStr
      // faster creation of the matrix for basic types
      case "real"
      case "integer"
      case "boolean" then
        let tmp = tempDecl(arrayTypeStr, &varDecls)
        let rows = '<%listLength(m.matrix)%>'
        let cols = '<%listLength(listGet(m.matrix, 1))%>'
        let matrix = (m.matrix |> row hasindex i0 =>
            let els = (row |> e hasindex j0 =>
              let expVar = daeExp(e, context, &preExp, &varDecls, &auxFunction)
              'put_<%typeStr%>_matrix_element(<%expVar%>, <%i0%>, <%j0%>, &<%tmp%>);' ;separator="\n")
          '<%els%>'
          ;separator="\n")
        let &preExp += '/* -- start: matrix[<%rows%>,<%cols%>] -- */<%\n%>'
        let &preExp += 'alloc_<%typeStr%>_array(&<%tmp%>, 2, <%rows%>, <%cols%>);<%\n%>'
        let &preExp += '<%matrix%><%\n%>'
        let &preExp += '/* -- end: matrix[<%rows%>,<%cols%>] -- */<%\n%>'
        tmp
      // everything else
      case _ then
        let &vars2 = buffer ""
        let &promote = buffer ""
        let catAlloc = (m.matrix |> row =>
          let tmp = tempDecl(arrayTypeStr, &varDecls)
          let vars = daeExpMatrixRow(row, arrayTypeStr, context,
                                 &promote, &varDecls, &auxFunction)
          let &vars2 += ', &<%tmp%>'
          'cat_alloc_<%arrayTypeStr%>(2, &<%tmp%>, <%listLength(row)%><%vars%>);'
          ;separator="\n")
        let &preExp += promote
        let &preExp += catAlloc
        let &preExp += "\n"
        let tmp = tempDecl(arrayTypeStr, &varDecls)
        let &preExp += 'cat_alloc_<%arrayTypeStr%>(1, &<%tmp%>, <%listLength(m.matrix)%><%vars2%>);<%\n%>'
        tmp
end daeExpMatrix;


template daeExpMatrixRow(list<Exp> row, String arrayTypeStr,
                         Context context, Text &preExp,
                         Text &varDecls, Text &auxFunction)
 "Helper to daeExpMatrix."
::=
  let &varLstStr = buffer ""

  let preExp2 = (row |> e =>
      let expVar = daeExp(e, context, &preExp, &varDecls, &auxFunction)
      let tmp = tempDecl(arrayTypeStr, &varDecls)
      let &varLstStr += ', &<%tmp%>'
      'promote_scalar_<%arrayTypeStr%>(<%expVar%>, 2, &<%tmp%>);'
    ;separator="\n")
  let &preExp2 += "\n"
  let &preExp += preExp2
  varLstStr
end daeExpMatrixRow;

template daeExpRange(Exp exp, Context context, Text &preExp,
                      Text &varDecls, Text &auxFunction)
 "Generates code for a range expression."
::=
  match exp
  case RANGE(__) then
    let ty_str = expTypeArray(ty)
    let start_exp = daeExp(start, context, &preExp, &varDecls, &auxFunction)
    let stop_exp = daeExp(stop, context, &preExp, &varDecls, &auxFunction)
    let tmp = tempDecl(ty_str, &varDecls)
    let step_exp = match step case SOME(stepExp) then daeExp(stepExp, context, &preExp, &varDecls, &auxFunction) else "1"
    let &preExp += 'create_<%ty_str%>_from_range(&<%tmp%>, <%start_exp%>, <%step_exp%>, <%stop_exp%>);<%\n%>'
    '<%tmp%>'
end daeExpRange;

template daeExpCast(Exp exp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for a cast expression."
::=
match exp
case CAST(__) then
  let expVar = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  match ty
  case T_INTEGER(__)   then '((modelica_integer)<%expVar%>)'
  case T_REAL(__)  then '((modelica_real)<%expVar%>)'
  case T_ENUMERATION(__)   then '((modelica_integer)<%expVar%>)'
  case T_BOOL(__)   then '((modelica_boolean)<%expVar%>)'
  case T_ARRAY(__) then
    let arrayTypeStr = expTypeArray(ty)
    let tvar = tempDecl(arrayTypeStr, &varDecls)
    let tevar = tempDecl(arrayTypeStr, &varDecls)
    let to = expTypeShort(ty)
    let from = expTypeFromExpShort(exp)
    let &preExp += '<%tevar%> = <%expVar%>;<%\n%>cast_<%from%>_array_to_<%to%>(&<%tevar%>, &<%tvar%>);<%\n%>'
    '<%tvar%>'
  case ty1 as T_COMPLEX(complexClassType=rec as RECORD(__)) then
    match typeof(exp)
      case ty2 as T_COMPLEX(__) then
        if intEq(listLength(ty1.varLst),listLength(ty2.varLst)) then expVar
        else
          let tmp = tempDecl(expTypeModelica(ty2),&varDecls)
          let res = tempDecl(expTypeModelica(ty1),&varDecls)
          let &preExp += '<%tmp%> = <%expVar%>;<%\n%>'
          let &preExp += ty1.varLst |> var as DAE.TYPES_VAR() => '<%res%>._<%var.name%> = <%tmp%>._<%var.name%>; /* cast */<%\n%>'
          res
  else
    '(<%expVar%>) /* could not cast, using the variable as it is */'
end daeExpCast;

template daeExpTsub(Exp inExp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for an tsub expression."
::=
  match inExp
  case TSUB(ix=1) then
    daeExp(exp, context, &preExp, &varDecls, &auxFunction)
  case TSUB(exp=CALL(attr=CALL_ATTR(ty=T_TUPLE(types=tys)))) then
    let v = tempDecl(expTypeArrayIf(listGet(tys,ix)), &varDecls)
    let additionalOutputs = List.restOrEmpty(tys) |> ty hasindex i1 fromindex 2 => if intEq(i1,ix) then ', &<%v%>' else ", NULL"
    let &preExp += if isArrayType(listGet(tys,ix)) then '<%v%>.dim_size = 0;<%\n%>'
    let res = daeExpCallTuple(exp, additionalOutputs, context, &preExp, &varDecls, &auxFunction)
    let &preExp += '<%res%>;<%\n%>'
    v
  case TSUB(__) then
    error(sourceInfo(), '<%printExpStr(inExp)%>: TSUB only makes sense if the subscripted expression is a function call of tuple type')
end daeExpTsub;

template daeExpRsub(Exp inExp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for an tsub expression."
::=
  match inExp
  case RSUB(__) then
    let res = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    let offset = intAdd(ix,1) // 1-based
    '(MMC_FETCH(MMC_OFFSET(MMC_UNTAGPTR(<%res%>), <%offset%>)))'
  case RSUB(__) then
    error(sourceInfo(), '<%printExpStr(inExp)%>: failed')
end daeExpRsub;

template daeExpAsub(Exp inExp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for an asub expression."
::=
  match expTypeFromExpShort(inExp)
  case "metatype" then
  // MetaModelica Array
    (match inExp case ASUB(exp=e, sub={idx}) then
      let e1 = daeExp(e, context, &preExp, &varDecls, &auxFunction)
      let idx1 = daeExp(idx, context, &preExp, &varDecls, &auxFunction)
      'arrayGet(<%e1%>,<%idx1%>) /* DAE.ASUB */')
  // Modelica Array
  else
  match inExp
  case ASUB(exp=ASUB(__)) then
    error(sourceInfo(),'Nested array subscripting *should* have been handled by the routine creating the asub, but for some reason it was not: <%printExpStr(exp)%>')

  // Faster asub: Do not construct a whole new array just to access one subscript
  case ASUB(exp=exp as ARRAY(scalar=true), sub={idx}) then
    let res = tempDecl(expTypeFromExpModelica(exp),&varDecls)
    let idx1 = daeExp(idx, context, &preExp, &varDecls, &auxFunction)
    let expl = (exp.array |> e hasindex i1 fromindex 1 =>
      let &caseVarDecls = buffer ""
      let &casePreExp = buffer ""
      let v = daeExp(e, context, &casePreExp, &caseVarDecls, &auxFunction)
      <<
      case <%i1%>: {
        <%&caseVarDecls%>
        <%&casePreExp%>
        <%res%> = <%v%>;
        break;
      }
      >> ; separator = "\n")
    let &preExp +=
    <<
    switch(<%idx1%>)
    { /* ASUB */
    <%expl%>
    default:
      throwStreamPrint(threadData, "Index %ld out of bounds [1..<%listLength(exp.array)%>] for array <%Util.escapeModelicaStringToCString(printExpStr(exp))%>", (long) <%idx1%>);
    }
    <%\n%>
    >>
    res

  case ASUB(exp=range as RANGE(ty=T_INTEGER(),step=NONE()), sub={idx}) then
    let res = tempDecl("modelica_integer", &varDecls)
    let idx1 = daeExp(idx, context, &preExp, &varDecls, &auxFunction)
    let start = daeExp(range.start, context, &preExp, &varDecls, &auxFunction)
    let stop = daeExp(range.stop, context, &preExp, &varDecls, &auxFunction)
    let &preExp += <<
    <%res%> = <%idx1%> + <%start%> - 1;
    if (<%res%> > <%stop%>) {
      throwStreamPrint(threadData, "Value %ld out of bounds for range <%Util.escapeModelicaStringToCString(printExpStr(range))%>", (long) <%res%>);
    }
    >>
    res

  case ASUB(exp=RANGE(ty=t), sub={idx}) then
    error(sourceInfo(),'ASUB_EASY_CASE type:<%unparseType(t)%> range:<%printExpStr(exp)%> index:<%printExpStr(idx)%>')

  case ASUB(exp=ecr as CREF(__), sub=subs) then
    let arrName = daeExpCrefRhs(buildCrefExpFromAsub(ecr, subs), context,
                              &preExp, &varDecls, &auxFunction)
    match context
    case FUNCTION_CONTEXT(__)  then
        arrName
    case PARALLEL_FUNCTION_CONTEXT(__)  then
        arrName
    else
        arrayScalarRhs(ecr.ty, subs, arrName, context, &preExp, &varDecls, &auxFunction)

  case ASUB(exp=e, sub=indexes) then
    let exp = daeExp(e, context, &preExp, &varDecls, &auxFunction)
    let typeShort = expTypeFromExpShort(e)
    match Expression.typeof(inExp)
    case T_ARRAY(__) then
      error(sourceInfo(),'ASUB non-scalar <%printExpStr(inExp)%>. The inner exp has type: <%unparseType(Expression.typeof(e))%>. After ASUB it is still an array: <%unparseType(Expression.typeof(inExp))%>.')
    else
      let expIndexes = (indexes |> index => '<%daeExpASubIndex(index, context, &preExp, &varDecls, &auxFunction)%>' ;separator=", ")
      '<%typeShort%>_get<%match listLength(indexes) case 1 then "" case i then '_<%i%>D'%>(<%exp%>, <%expIndexes%>)'

  else
    error(sourceInfo(),'OTHER_ASUB <%printExpStr(inExp)%>')
end daeExpAsub;

template daeExpASubIndex(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
match exp
  case ICONST(__) then incrementInt(integer,-1)
  case ENUM_LITERAL(__) then incrementInt(index,-1)
  else '(<%daeExp(exp,context,&preExp,&varDecls, &auxFunction)%>)-1'
end daeExpASubIndex;

template daeExpCallPre(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
  "Generates code for an asub of a cref, which becomes cref + offset."
::=
  match exp
  /*we use daeExpCrefLhs because daeExpCrefRhs returns with a cast.
   will reslut in '$P$PRE(modelica_integer)$A$B...
   pre() functions should actaully be eliminated in backend and $PRE prepened as ident
   in all cases. (now it's done some places but not in others.)*/
  case cr as CREF(__) then
    '$P$PRE<%daeExpCrefLhs(exp, context, &preExp, &varDecls, &auxFunction)%>'
  else
    error(sourceInfo(), 'Code generation does not support pre(<%printExpStr(exp)%>)')
end daeExpCallPre;

template daeExpCallStart(Exp exp, Context context, Text &preExp,
                       Text &varDecls, Text &auxFunction)
  "Generates code for an asub of a cref, which becomes cref + offset."
::=
  match exp
  case cr as CREF(__) then
    '$P$ATTRIBUTE<%cref(cr.componentRef)%>.start'
  case ASUB(exp = cr as CREF(__), sub = {sub_exp}) then
    let offset = daeExp(sub_exp, context, &preExp, &varDecls, &auxFunction)
    let cref = cref(cr.componentRef)
    '*(&$P$ATTRIBUTE<%cref(cr.componentRef)%>.start + <%offset%>)'
  else
    error(sourceInfo(), 'Code generation does not support start(<%printExpStr(exp)%>)')
end daeExpCallStart;


template daeExpSize(Exp exp, Context context, Text &preExp,
                    Text &varDecls, Text &auxFunction)
 "Generates code for a size expression."
::=
  match exp
  case SIZE(exp=CREF(__), sz=SOME(dim)) then
    let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    let dimPart = daeExp(dim, context, &preExp, &varDecls, &auxFunction)
    let resVar = tempDecl("modelica_integer", &varDecls)
    let &preExp += '<%resVar%> = size_of_dimension_base_array(<%expPart%>, <%dimPart%>);<%\n%>'
    resVar
  case SIZE(exp=CREF(__)) then
    let expPart = daeExp(exp, context, &preExp, &varDecls, &auxFunction)
    let resVar = tempDecl("integer_array", &varDecls)
    let &preExp += 'sizes_of_dimensions_base_array(&<%expPart%>, &<%resVar%>);<%\n%>'
    resVar
  /* array of zero? */
  case SIZE(exp=ARRAY(array = {})) then
    let resVar = tempDecl("modelica_integer", &varDecls)
    let &preExp += '<%resVar%> = 0;<%\n%>'
    resVar
  else error(sourceInfo(), printExpStr(exp) + " not implemented")
end daeExpSize;


template daeExpReduction(Exp exp, Context context, Text &preExp,
                         Text &varDecls, Text &auxFunction)
 "Generates code for a reduction expression. The code is quite messy because it handles all
  special reduction functions (list, listReverse, array) and handles both list and array as input"
::=
  match exp
  case r as REDUCTION(reductionInfo=ri as REDUCTIONINFO(iterType=THREAD()),iterators=iterators)
  case r as REDUCTION(reductionInfo=ri as REDUCTIONINFO(iterType=COMBINE()),iterators=iterators as {_}) then
  (
  let &tmpVarDecls = buffer ""
  let &tmpExpPre = buffer ""
  let &bodyExpPre = buffer ""
  let &rangeExpPre = buffer ""
  let arrayTypeResult = expTypeFromExpArray(r)
  let arrIndex = match ri.path case IDENT(name="array") then tempDecl("int",&tmpVarDecls)
  let foundFirst = if not ri.defaultValue then tempDecl("int",&tmpVarDecls)
  let resType = expTypeArrayIf(typeof(exp))
  let res = contextCref(makeUntypedCrefIdent(ri.resultName), context, &auxFunction)
  let &tmpVarDecls += '<%resType%> <%res%>;<%\n%>'
  let resTmp = tempDecl(resType,&varDecls)
  let &preDefault = buffer ""
  let resTail = (match ri.path case IDENT(name="list") then tempDecl("modelica_metatype*",&tmpVarDecls))
  let defaultValue = (match ri.path
    case IDENT(name="array") then ""
    else (match ri.defaultValue
          case SOME(v) then daeExp(valueExp(v),context,&preDefault,&tmpVarDecls, &auxFunction)))
  let reductionBodyExpr = contextCref(makeUntypedCrefIdent(ri.foldName), context, &auxFunction)
  let bodyExprType = expTypeArrayIf(typeof(r.expr))
  let reductionBodyExprWork = daeExp(r.expr, context, &bodyExpPre, &tmpVarDecls, &auxFunction)
  let &tmpVarDecls += '<%bodyExprType%> <%reductionBodyExpr%>;<%\n%>'
  let &bodyExpPre += '<%reductionBodyExpr%> = <%reductionBodyExprWork%>;<%\n%>'
  let foldExp = (match ri.path
    case IDENT(name="list") then
    <<
    *<%resTail%> = mmc_mk_cons(<%reductionBodyExpr%>,0);
    <%resTail%> = &MMC_CDR(*<%resTail%>);
    >>
    case IDENT(name="listReverse") then // This is too easy; the damn list is already in the correct order
      '<%res%> = mmc_mk_cons(<%reductionBodyExpr%>,<%res%>);'
    case IDENT(name="array") then
      match typeof(r.expr)
        case T_COMPLEX(complexClassType = record_state) then
          let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
          '*((<%rec_name%>*)generic_array_element_addr(&<%res%>, sizeof(<%rec_name%>), 1, <%arrIndex%>++)) = <%reductionBodyExpr%>;'
        case T_ARRAY(__) then
          let tmp = tempDecl("index_spec_t", &varDecls)
          let nridx_str = intAdd(1,listLength(dims))
          let idx_str = (dims |> dim => ", (1), (int*)0, 'W'")
          <<
          create_index_spec(&<%tmp%>, <%nridx_str%>, (0), make_index_array(1, (int) <%arrIndex%>++), 'S'<%idx_str%>);
          indexed_assign_<%expTypeArray(ty)%>(<%reductionBodyExpr%>, &<%res%>, &<%tmp%>);
          >>
        else
          '*(<%arrayTypeResult%>_element_addr1(&<%res%>, 1, <%arrIndex%>++)) = <%reductionBodyExpr%>;'
    else match ri.foldExp case SOME(fExp) then
      let &foldExpPre = buffer ""
      let fExpStr = daeExp(fExp, context, &bodyExpPre, &tmpVarDecls, &auxFunction)
      if not ri.defaultValue then
      <<
      if(<%foundFirst%>)
      {
        <%res%> = <%fExpStr%>;
      }
      else
      {
        <%res%> = <%reductionBodyExpr%>;
        <%foundFirst%> = 1;
      }
      >>
      else '<%res%> = <%fExpStr%>;')
  let endLoop = tempDecl("int",&tmpVarDecls)
  let loopHeadIter = (iterators |> iter as REDUCTIONITER(__) =>
    let identType = expTypeFromExpModelica(iter.exp)
    let arrayType = expTypeFromExpArray(iter.exp)
    let loopVar = '<%iter.id%>_loopVar'
    let &guardExpPre = buffer ""
    let &tmpVarDecls += (match identType
      case "modelica_metatype" then 'modelica_metatype <%loopVar%> = 0;<%\n%>'
      else '<%arrayType%> <%loopVar%>;<%\n%>')
    let firstIndex = match identType case "modelica_metatype" then (if isMetaArray(iter.exp) then tempDecl("int",&tmpVarDecls) else "") else tempDecl("int",&tmpVarDecls)
    let rangeExp = daeExp(iter.exp,context,&rangeExpPre,&tmpVarDecls, &auxFunction)
    let &rangeExpPre += '<%loopVar%> = <%rangeExp%>;<%\n%>'
    let &rangeExpPre += if firstIndex then '<%firstIndex%> = 1;<%\n%>'
    let guardCond = (match iter.guardExp case SOME(grd) then daeExp(grd, context, &guardExpPre, &tmpVarDecls, &auxFunction) else "1")
    let iteratorName = contextIteratorName(iter.id, context)
    let &tmpVarDecls += '<%identType%> <%iteratorName%>;<%\n%>'
    let guardExp =
      <<
      <%&guardExpPre%>
      if(<%guardCond%>) { /* found non-guarded */
        <%endLoop%>--;
        break;
      }
      >>
    (match identType
      case "modelica_metatype" then
      (if isMetaArray(iter.exp) then
        <<
        while (<%firstIndex%> <= arrayLength(<%loopVar%>)) {
          <%iteratorName%> = arrayGet(<%loopVar%>, <%firstIndex%>++);
          <%guardExp%>
        }
        >>
      else
        <<
        while (!listEmpty(<%loopVar%>)) {
          <%iteratorName%> = MMC_CAR(<%loopVar%>);
          <%loopVar%> = MMC_CDR(<%loopVar%>);
          <%guardExp%>
        }
        >>
      )
      else
      let addr = match iter.ty
        case T_ARRAY(ty=T_COMPLEX(complexClassType = record_state)) then
          let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
          '*((<%rec_name%>*)generic_array_element_addr(&<%loopVar%>, sizeof(<%rec_name%>), 1, <%firstIndex%>++))'
        else
          '*(<%arrayType%>_element_addr1(&<%loopVar%>, 1, <%firstIndex%>++))'
      <<
      while(<%firstIndex%> <= size_of_dimension_base_array(<%loopVar%>, 1)) {
        <%iteratorName%> = <%addr%>;
        <%guardExp%>
      }
      >>))
  let firstValue = (match ri.path
     case IDENT(name="array") then
       let length = tempDecl("int",&tmpVarDecls)
       let &rangeExpPre += '<%length%> = 0;<%\n%>'
       let _ = (iterators |> iter as REDUCTIONITER(__) =>
         let loopVar = '<%iter.id%>_loopVar'
         let identType = expTypeFromExpModelica(iter.exp)
         let &rangeExpPre += '<%length%> = modelica_integer_max(<%length%>,<%match identType case "modelica_metatype" then (if isMetaArray(iter.exp) then 'arrayLength(<%loopVar%>)' else 'listLength(<%loopVar%>)') else 'size_of_dimension_base_array(<%loopVar%>, 1)'%>);<%\n%>'
         "")
       <<
       <%arrIndex%> = 1;
       <% match typeof(r.expr)
        case T_COMPLEX(complexClassType = record_state) then
          let rec_name = '<%underscorePath(ClassInf.getStateName(record_state))%>'
          'alloc_generic_array(&<%res%>,sizeof(<%rec_name%>),1,<%length%>);'
        case T_ARRAY(__) then
          let dimSizes = dims |> dim => match dim
            case DIM_INTEGER(__) then ', <%integer%>'
            case DIM_BOOLEAN(__) then ", 2"
            case DIM_ENUM(__) then ', <%size%>'
            else error(sourceInfo(), 'array reduction unable to generate code for element of unknown dimension sizes; type <%unparseType(typeof(r.expr))%>: <%ExpressionDump.printExpStr(r.expr)%>')
            ; separator = ", "
          'alloc_<%arrayTypeResult%>(&<%res%>, <%intAdd(1,listLength(dims))%>, <%length%><%dimSizes%>);'
        else
          'simple_alloc_1d_<%arrayTypeResult%>(&<%res%>,<%length%>);'%>
       >>
     else if ri.defaultValue then
     <<
     <%&preDefault%>
     <%res%> = <%defaultValue%>; /* defaultValue */
     >>
     else
     <<
     <%foundFirst%> = 0; /* <%dotPath(ri.path)%> lacks default-value */
     >>)
  let loop =
    <<
    while(1) {
      <%endLoop%> = <%listLength(iterators)%>;
      <%loopHeadIter%>
      if (<%endLoop%> == 0) {
        <%&bodyExpPre%>
        <%foldExp%>
      } <% match iterators case _::_ then
      <<
      else if (<%endLoop%> == <%listLength(iterators)%>) {
        break;
      } else {
        <%generateThrow()%>;
      }
      >> %>
    }
    >>
  let &preExp += <<
  {
    <%&tmpVarDecls%>
    <%&rangeExpPre%>
    <%firstValue%>
    <% if resTail then '<%resTail%> = &<%res%>;' %>
    <%loop%>
    <% if not ri.defaultValue then 'if (!<%foundFirst%>) <%generateThrow()%>;' %>
    <% if resTail then '*<%resTail%> = mmc_mk_nil();' %>
    <% resTmp %> = <% res %>;
  }<%\n%>
  >>
  resTmp)
  else error(sourceInfo(), 'Code generation does not support multiple iterators: <%printExpStr(exp)%>')
end daeExpReduction;

template daeExpMatch(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a match expression."
::=
match exp
case exp as MATCHEXPRESSION(__) then
  let res = match et
    case T_NORETCALL(__) then error(sourceInfo(), 'match expression not returning anything should be caught in a noretcall statement and not reach this code: <%printExpStr(exp)%>')
    case T_TUPLE(types={}) then error(sourceInfo(), 'match expression returning an empty tuple should be caught in a noretcall statement and not reach this code: <%printExpStr(exp)%>')
    else tempDeclZero(expTypeModelica(et), &varDecls)
  let startIndexOutputs = "ERROR_INDEX"
  daeExpMatch2(exp,listExpLength1,res,startIndexOutputs,context,&preExp,&varDecls,&auxFunction)
end daeExpMatch;

template daeExpMatch2(Exp exp, list<Exp> tupleAssignExps, Text res, Text startIndexOutputs, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a match expression."
::=
match exp
case exp as MATCHEXPRESSION(__) then
  let () = codegenPushTryThrowIndex(System.tmpTick())
  let goto = 'goto_<%codegenPeekTryThrowIndex()%>'
  let &preExpInner = buffer ""
  let &preExpRes = buffer ""
  let &varDeclsInput = buffer ""
  let &varDeclsInner = buffer ""
  let &varFrees = buffer ""
  let &ignore = buffer ""
  let ignore2 = (elementVars(localDecls) |> var =>
      varInit(var, "", &varDeclsInner, &preExpInner, &varFrees, &auxFunction)
    )
  let prefix = 'tmp<%System.tmpTick()%>'
  let &preExpInput = buffer ""
  let &expInput = buffer ""
  // get the current index of tmpMeta and reserve N=listLength(inputs) values in it!
  let startIndexInputs = '<%System.tmpTickIndexReserve(1, listLength(inputs))%>'
  let ignore3 = (List.threadTuple(inputs,aliases) |> (exp,alias) hasindex i0 =>
    let typ = '<%expTypeFromExpModelica(exp)%>'
    let decl = tempDeclMatchInput(typ, prefix, startIndexInputs, i0, &varDeclsInput)
    let &expInput += '<%decl%> = <%daeExp(exp, context, &preExpInput, &varDeclsInput, &auxFunction)%>;<%\n%>'
    let &expInput += alias |> a => let &varDeclsInput += '<%typ%> _<%a%>;' '_<%a%> = <%decl%>;' ; separator="\n"
    ""; empty)
  let ix = match exp.matchType
    case MATCH(switch=SOME((switchIndex,ty as T_STRING(__),div))) then
      let matchInputVar = getTempDeclMatchInputName(exp.inputs, prefix, startIndexInputs, switchIndex)
      'stringHashDjb2Mod(<%matchInputVar%>,<%div%>)'
    case MATCH(switch=SOME((switchIndex,ty as T_METATYPE(__),_))) then
      let matchInputVar = getTempDeclMatchInputName(exp.inputs, prefix, startIndexInputs, switchIndex)
      'valueConstructor(<%matchInputVar%>)'
    case MATCH(switch=SOME((switchIndex,ty as T_INTEGER(__),_))) then
      let matchInputVar = getTempDeclMatchInputName(exp.inputs, prefix, startIndexInputs, switchIndex)
      '<%matchInputVar%>'
    case MATCH(switch=SOME(_)) then
      error(sourceInfo(), 'Unknown switch: <%printExpStr(exp)%>')
    else tempDecl('volatile mmc_switch_type', &varDeclsInner)
  let done = tempDecl('int', &varDeclsInner)
  let &preExp +=
      <<
      <%endModelicaLine()%>
      { /* <% match exp.matchType case MATCHCONTINUE(__) then "matchcontinue expression" case MATCH(__) then "match expression" %> */
        <%varDeclsInput%>
        <%preExpInput%>
        <%expInput%>
        {
          <%varDeclsInner%>
          <%preExpInner%>
          <%match exp.matchType
          case MATCH(switch=SOME(_)) then '<%done%> = 0;<%\n%>{'
          else
          <<
          <%ix%> = 0;
          <%done%> = 0;
          <% match exp.matchType case MATCHCONTINUE(__) then
          /* One additional MMC_TRY_INTERNAL() for each caught exception
           * You would expect you could do the setjmp only once, but some counters I guess are stored in registers and would need to become volatile
           * This is still a lot faster than doing MMC_TRY_INTERNAL() inside the for-loop
           */
          <<
          MMC_TRY_INTERNAL(mmc_jumper)
          <%prefix%>_top:
          threadData->mmc_jumper = &new_mmc_jumper;
          >>
          %>
          for (; <%ix%> < <%listLength(exp.cases)%> && !<%done%>; <%ix%>++) {
          >>
          %>
            switch (MMC_SWITCH_CAST(<%ix%>)) {
            <%daeExpMatchCases(exp.cases, tupleAssignExps, exp.matchType, ix, res, startIndexOutputs, prefix, startIndexInputs, exp.inputs, done, context, &varDecls, &auxFunction, System.tmpTickIndexReserve(1,0) /* Returns the current MM tick */)%>
            }
            goto <%prefix%>_end;
            <%prefix%>_end: ;
          }<%let() = codegenPopTryThrowIndex() ""%>
          goto <%goto%>;
          <%goto%>:;
          <% match exp.matchType case MATCHCONTINUE(__) then
          <<
          MMC_CATCH_INTERNAL(mmc_jumper);
          if (!<%done%> && ++<%ix%> < <%listLength(exp.cases)%>) {
            goto <%prefix%>_top;
          }
          >>
          %>
          if (!<%done%>) <%generateThrow()%>;
        }
      }
      >>
  res
end daeExpMatch2;

template daeExpMatchCases(list<MatchCase> cases, list<Exp> tupleAssignExps, DAE.MatchType ty, Text ix, Text res, Text startIndexOutputs, Text prefix, Text startIndexInputs, list<Exp> inputs, Text done, Context context, Text &varDecls, Text &auxFunction, Integer startTmpTickIndex)
::=
  cases |> c as CASE(__) hasindex i0 =>
  let() = System.tmpTickSetIndex(startTmpTickIndex,1)
  // Susan doesn't let us do this outside the loop...
  let lastSwitchIndex = (match ty
    case MATCH(switch=SOME((n,ty as T_STRING(__),div))) then
      (match List.last(cases)
      case last as CASE(__) then
        (match switchIndex(listGet(last.patterns,n),div)
          case "default" then 'goto <%prefix%>_default'
          else 'goto <%prefix%>_end'))
    else 'goto <%prefix%>_end')
  let onPatternFail = (match ty
    case MATCH(switch=SOME((switchIndex,ty as T_STRING(__),div))) then
      lastSwitchIndex
    else 'goto <%prefix%>_end')
  let &varDeclsCaseInner = buffer ""
  let &preExpCaseInner = buffer ""
  let &assignments = buffer ""
  let &preRes = buffer ""
  let &varFrees = buffer ""
  let patternMatching = (sortPatternsByComplexity(c.patterns) |> (lhs,i0) => patternMatch(lhs,'<%getTempDeclMatchInputName(inputs, prefix, startIndexInputs, i0)%>', onPatternFail, &varDeclsCaseInner, &assignments); empty)
  let() = System.tmpTickSetIndex(startTmpTickIndex,1)
  let stmts = (c.body |> stmt => algStatement(stmt, context, &varDeclsCaseInner, &auxFunction); separator="\n")
  let &preGuardCheck = buffer ""
  let guardCheck = (match c.patternGuard case SOME(exp) then
    <<
    /* Check guard condition after assignments */
    if (!<%daeExp(exp,context,&preGuardCheck,&varDeclsCaseInner, &auxFunction)%>) <%onPatternFail%>;<%\n%>
    >>)
  let caseRes = (match c.result
    case SOME(TUPLE(PR=exps)) then
      (exps |> e hasindex i1 fromindex 1 =>
      '<%getTempDeclMatchOutputName(exps, res, startIndexOutputs, i1)%> = <%daeExp(e,context,&preRes,&varDeclsCaseInner, &auxFunction)%>;<%\n%>')
    case SOME(exp as CALL(attr=CALL_ATTR(tailCall=TAIL(__)))) then
      daeExp(exp, context, &preRes, &varDeclsCaseInner, &auxFunction)
    case SOME(exp as CALL(attr=CALL_ATTR(tuple_=true))) then
      let additionalOutputs = List.restOrEmpty(tupleAssignExps) |> cr hasindex i0 fromindex 2 /* starting with second element */ =>
        ', &<%getTempDeclMatchOutputName(tupleAssignExps, res, startIndexOutputs, i0)%>'
      let retStruct = daeExpCallTuple(exp, additionalOutputs, context, &preRes, &varDeclsCaseInner, &auxFunction)
      let callRet = match tupleAssignExps
        case {} then '<%retStruct%>;<%\n%>'
        case e::_ then '<%getTempDeclMatchOutputName(tupleAssignExps, res, startIndexOutputs, 1)%> = <%retStruct%>;<%\n%>'
      callRet
    case SOME(e) then '<%res%> = <%daeExp(e,context,&preRes,&varDeclsCaseInner, &auxFunction)%>;<%\n%>')
  let _ = (elementVars(c.localDecls) |> var => varInit(var, "", &varDeclsCaseInner, &preExpCaseInner, &varFrees, &auxFunction))
  <<<%match ty case MATCH(switch=SOME((n,_,ea)))
    then
      let name = switchIndex(listGet(c.patterns,n),ea)
      (match name
        case "default" then
          <<
          <%name%>: {
            <%prefix%>_default: OMC_LABEL_UNUSED;
          >>
        else
          '<%name%>: {')
    else
      'case <%i0%>: {'%>
    <%varDeclsCaseInner%>
    <%preExpCaseInner%>
    <%patternMatching%>
    <%assignments%>
    <%&preGuardCheck%>
    <%guardCheck%>
    <% match c.jump
       case 0 then "/* Pattern matching succeeded */"
       else '<%ix%> += <%c.jump%>; /* Pattern matching succeeded; we may skip some cases if we fail */'
    %>
    <%stmts%>
    <%modelicaLine(c.resultInfo)%>
    <% if c.result then '<%preRes%><%caseRes%>' else '<%generateThrow()%>;<%\n%>' %>
    <%endModelicaLine()%>
    <%done%> = 1;
    break;
  }<%\n%>
  >>
end daeExpMatchCases;

template switchIndex(Pattern pattern, Integer extraArg)
::=
  match pattern
    case PAT_CALL(__) then 'case <%getValueCtor(index)%>'
    case PAT_CONSTANT(exp=e as SCONST(__)) then 'case <%stringHashDjb2Mod(e.string,extraArg)%> /* <%e.string%> */'
    case PAT_CONSTANT(exp=e as ICONST(__)) then 'case <%e.integer%>'
    else 'default'
end switchIndex;

template daeExpBox(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a match expression."
::=
match exp
case BOX(__) then
  let ty = if isArrayType(typeof(exp)) then "modelica_array" else expTypeFromExpShort(exp)
  let res = daeExp(exp,context,&preExp,&varDecls, &auxFunction)
  'mmc_mk_<%ty%>(<%res%>)'
end daeExpBox;

template daeExpUnbox(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
 "Generates code for a match expression."
::=
match exp
case exp as UNBOX(__) then
  let ty = expTypeShort(exp.ty)
  let res = daeExp(exp.exp,context,&preExp,&varDecls, &auxFunction)
  'mmc_unbox_<%ty%>(<%res%>)'
end daeExpUnbox;

template daeExpSharedLiteral(Exp exp)
 "Generates code for a match expression."
::=
match exp case exp as SHARED_LITERAL(__) then '_OMC_LIT<%exp.index%>'
end daeExpSharedLiteral;

/* Dimensions need to return expressions that are different than for normal expressions.
 * The reason is that dimensions use 1-based indexing, but Boolean indexes start at 0
 */
template daeDimensionExp(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  let res = daeExp(exp,context,&preExp,&varDecls,&auxFunction)
  match expTypeFromExpModelica(exp)
  case "modelica_boolean" then '(<%res%>+1)'
  else '/* <%expTypeFromExpModelica(exp)%> */ <%res%>'
end daeDimensionExp;

template daeSubscriptExp(Exp exp, Context context, Text &preExp, Text &varDecls, Text &auxFunction)
::=
  let res = daeExp(exp,context,&preExp,&varDecls,&auxFunction)
  match expTypeFromExpModelica(exp)
  case "modelica_boolean" then '(<%res%>+1)'
  else '<%res%>' /* <%expTypeFromExpModelica(exp)%> */
end daeSubscriptExp;

annotation(__OpenModelica_Interface="backend");
end CodegenCFunctions;

// vim: filetype=susan sw=2 sts=2
