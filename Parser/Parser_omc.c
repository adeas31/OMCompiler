/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2010, Link�pings University,
 * Department of Computer and Information Science,
 * SE-58183 Link�ping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THIS OSMC PUBLIC
 * LICENSE (OSMC-PL). ANY USE, REPRODUCTION OR DISTRIBUTION OF
 * THIS PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THE OSMC
 * PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Link�pings University, either from the above address,
 * from the URL: http://www.ida.liu.se/projects/OpenModelica
 * and in the OpenModelica distribution.
 *
 * This program is distributed  WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

#if defined(_MSC_VER) || defined(__MINGW32__)
 #define WIN32_LEAN_AND_MEAN
 #include <windows.h>
#endif

#include "meta_modelica.h"
#include "OpenModelicaBootstrappingHeader.h"
#include "parse.c"

void* ParserExt_parse(const char* filename, const char* infoname, int acceptedGrammar, int langStd, const char* encoding, int runningTestsuite)
{
  int flags = PARSE_MODELICA;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseFile(filename, infoname, flags, encoding, langStd, runningTestsuite);
  if (res == NULL)
    MMC_THROW();
  // printAny(res);
  return res;
}

void* ParserExt_parseexp(const char* filename, const char* infoname, int acceptedGrammar, int langStd, int runningTestsuite)
{
  int flags = PARSE_EXPRESSION;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseFile(filename, infoname, flags, "UTF-8", langStd, runningTestsuite);
  if (res == NULL)
    MMC_THROW();
  return res;
}

void* ParserExt_parsestring(const char* data, const char* filename, int acceptedGrammar, int langStd, int runningTestsuite)
{
  int flags = PARSE_MODELICA;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseString(data, filename, flags, langStd, runningTestsuite);
  if (res != NULL) {
    return res;
  } else {
    MMC_THROW();
  }
}

void* ParserExt_parsestringexp(const char* data, const char* filename, int acceptedGrammar, int langStd, int runningTestsuite)
{
  int flags = PARSE_EXPRESSION;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseString(data, filename, flags, langStd, runningTestsuite);
  if (res != NULL) {
    return res;
  } else {
    MMC_THROW();
  }
}

void* ParserExt_stringPath(const char* data, const char* filename, int acceptedGrammar, int langStd, int runningTestsuite)
{
  int flags = PARSE_PATH;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseString(data, filename, flags, langStd, runningTestsuite);
  if (res != NULL) {
    return res;
  } else {
    MMC_THROW();
  }
}

void* ParserExt_stringCref(const char* data, const char* filename, int acceptedGrammar, int langStd, int runningTestsuite)
{
  int flags = PARSE_CREF;
  if(acceptedGrammar == 2) flags |= PARSE_META_MODELICA;
  else if(acceptedGrammar == 3) flags |= PARSE_PARMODELICA;
  else if(acceptedGrammar == 4) flags |= PARSE_OPTIMICA;

  void *res = parseString(data, filename, flags, langStd, runningTestsuite);
  if (res != NULL) {
    return res;
  } else {
    MMC_THROW();
  }
}
