/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package File

class File
  extends ExternalObject;
  function constructor
    output File file;
  external "C" file=om_file_new() annotation(Include="
#ifndef __OMC_FILE_NEW
#define __OMC_FILE_NEW
#include <stdio.h>
#include <gc.h>
static inline void* om_file_new()
{
  return GC_malloc(sizeof(FILE*));
}
#endif
");
end constructor;
  function destructor
    input File file;
  external "C" om_file_free(file) annotation(Include="
#ifndef __OMC_FILE_FREE
#define __OMC_FILE_FREE
#include <stdio.h>
static inline void om_file_free(FILE **file)
{
  if (*file) {
    fclose(*file);
    *file = 0;
  }
  GC_free(file);
}
#endif
");
  end destructor;
end File;

type Mode = enumeration(Read,Write);

function open
  input File file;
  input String filename;
  input Mode mode = Mode.Read;
external "C" om_file_open(file,filename,mode) annotation(Include="
#ifndef __OMC_FILE_OPEN
#define __OMC_FILE_OPEN
#include <stdio.h>
#include <errno.h>
#include \"ModelicaUtilities.h\"
static inline void om_file_open(FILE **file,const char *filename,int mode)
{
  if (*file) {
    fclose(*file);
  }
  *file = fopen(filename, mode == 1 ? \"rb\" : \"wb\");
  if (0 == *file) {
    ModelicaFormatError(\"Failed to open file %s with mode %d: %s\\n\", filename, mode, strerror(errno));
  }
}
#endif
");
end open;

function write
  input File file;
  input String data;
external "C" om_file_write(file,data) annotation(Include="
#ifndef __OMC_FILE_WRITE
#define __OMC_FILE_WRITE
#include <stdio.h>
#include <errno.h>
#include \"ModelicaUtilities.h\"
static inline void om_file_write(FILE **file,const char *data)
{
  if (!*file) {
    ModelicaError(\"Failed to write to file (not open)\");
  }
  if (EOF == fputs(data,*file)) {
    ModelicaFormatError(\"Failed to write to file: %s\\n\", strerror(errno));
  }
}
#endif
");
end write;

type Escape = enumeration(C "Escapes C strings (minimally): \\n and \"",
                          JSON "Escapes JSON strings (quotes and control characters)",
                          XML "Escapes strings to XML text");

function writeEscape
  input File file;
  input String data;
  input Escape escape;
external "C" om_file_write_escape(file,data,escape) annotation(Include="
#ifndef __OMC_FILE_WRITE_ESCAPE
#define __OMC_FILE_WRITE_ESCAPE
#include <stdio.h>
#include <errno.h>
#include \"ModelicaUtilities.h\"
enum escape_t {
  C=1,
  JSON,
  XML
};
#define ERROR_WRITE() ModelicaFormatError(\"Failed to write to file: %s\\n\", strerror(errno))
static inline void om_file_write_escape(FILE **file,const char *data,enum escape_t escape)
{
  if (!*file) {
    ModelicaError(\"Failed to write to file (not open)\\n\");
  }
  switch (escape) {
  case C:
    while (*data) {
      if (*data == '\\n') {
        if (fputs(\"\\\\n\",*file)<0) ERROR_WRITE();
      } else if (*data == '\"') {
        if (fputs(\"\\\\\\\"\",*file)<0) ERROR_WRITE();
      } else {
        if (putc(*data,*file)<0) ERROR_WRITE();
      }
      data++;
    }
    break;
  case JSON:
    while (*data) {
      switch (*data) {
      case '\\\"': if (fputs(\"\\\\\\\"\",*file)<0) ERROR_WRITE();break;
      case '\\\\': if (fputs(\"\\\\\\\\\",*file)<0) ERROR_WRITE();break;
      case '\\n': if (fputs(\"\\\\n\",*file)<0) ERROR_WRITE();break;
      case '\\b': if (fputs(\"\\\\b\",*file)<0) ERROR_WRITE();break;
      case '\\f': if (fputs(\"\\\\f\",*file)<0) ERROR_WRITE();break;
      case '\\r': if (fputs(\"\\\\r\",*file)<0) ERROR_WRITE();break;
      case '\\t': if (fputs(\"\\\\t\",*file)<0) ERROR_WRITE();break;
      default:
        if (*data < ' ') { /* Escape other control characters */
          if (fprintf(*file, \"\\\\u%04x\",*data)<0) ERROR_WRITE();
        } else {
          if (putc(*data,*file)<0) ERROR_WRITE();
        }
      }
      data++;
    }
    break;
  case XML:
    while (*data) {
      switch (*data) {
      case '<': if (fputs(\"&lt;\",*file)<0) ERROR_WRITE();break;
      case '>': if (fputs(\"&gt;\",*file)<0) ERROR_WRITE();break;
      case '\"': if (fputs(\"&#34;\",*file)<0) ERROR_WRITE();break;
      case '&': if (fputs(\"&amp;\",*file)<0) ERROR_WRITE();break;
      case '\\'': if (fputs(\"&#39;\",*file)<0) ERROR_WRITE();break;
      default:
        if (putc(*data,*file)<0) ERROR_WRITE();
      }
      data++;
    }
    break;
  default:
    ModelicaFormatError(\"No such escape enumeration: %d\\n\", escape);
  }
}
#endif
");
end writeEscape;

type Whence = enumeration(Set "SEEK_SET 0=start of file",Current "SEEK_CUR 0=current byte",End "SEEK_END 0=end of file");

function seek
  input File file;
  input Integer offset;
  input Whence whence = Whence.Set;
  output Boolean success;
external "C" success = om_file_seek(file,offset,whence) annotation(Include="
#ifndef __OMC_FILE_SEEK
#define __OMC_FILE_SEEK
#include <stdio.h>
#include \"ModelicaUtilities.h\"
enum whence_t {
  OMC_SEEK_SET=1,
  OMC_SEEK_CURRENT,
  OMC_SEEK_END
};
static inline int om_file_seek(FILE **file,int offset,enum whence_t whence)
{
  if (!*file) {
    return 0;
  }
  return 0==fseek(*file,offset,whence == OMC_SEEK_SET ? SEEK_SET : whence == OMC_SEEK_CURRENT ? OMC_SEEK_CURRENT : SEEK_END);
}
#endif
");
end seek;

package Examples

  model WriteToFile
    File file = File();
  initial algorithm
    open(file,"abc.txt",Mode.Write);
    write(file,"def.fafaf\n");
    writeEscape(file,"xx<def.\"\nfaf>af\n",escape=Escape.JSON);
  annotation(experiment(StopTime=0));
  end WriteToFile;

end Examples;

annotation(__OpenModelica_Interface="util");
end File;
