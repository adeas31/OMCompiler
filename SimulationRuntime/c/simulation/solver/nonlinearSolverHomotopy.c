/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THE BSD NEW LICENSE OR THE
 * GPL VERSION 3 LICENSE OR THE OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the OSMC (Open Source Modelica Consortium)
 * Public License (OSMC-PL) are obtained from OSMC, either from the above
 * address, from the URLs: http://www.openmodelica.org or
 * http://www.ida.liu.se/projects/OpenModelica, and in the OpenModelica
 * distribution. GNU version 3 is obtained from:
 * http://www.gnu.org/copyleft/gpl.html. The New BSD License is obtained from:
 * http://www.opensource.org/licenses/BSD-3-Clause.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, EXCEPT AS
 * EXPRESSLY SET FORTH IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE
 * CONDITIONS OF OSMC-PL.
 *
 */

/*! \file nonlinearSolverHomotopy.c
*  \author bbachmann
*/

#include <math.h>
#include <stdlib.h>
#include <string.h> /* memcpy */

#include "simulation/simulation_info_xml.h"
#include "util/omc_error.h"
#include "util/varinfo.h"
#include "model_help.h"
#include "meta/meta_modelica.h"
#include "util/write_csv.h"

#include "nonlinearSystem.h"
#include "nonlinearSolverHomotopy.h"
#include "nonlinearSolverHybrd.h"

/*! \typedef DATA_HOMOTOPY
 * define memory structure for nonlinear system solver
 *  \author bbachmann
 */
typedef struct DATA_HOMOTOPY
{
  int initialized; /* 1 = initialized, else = 0*/

  int n; /* dimension; n == size */
  int m; /* dimension: m == size+1 */

  double xtol; /* tolerance for updating solution vector */
  double ftol; /* tolerance fo accepting accuracy */

  double error_f;

  double* resScaling; /* residual scaling */
  double* fvecScaled; /* function values scaled */
  double* hvecScaled; /* function values scaled */
  double* dxScaled;   /* scaled solution vector */

  double* minValue; /* min-attribute of variable, only pointer */
  double* maxValue; /* max-attribute of variable, only pointer */
  double* xScaling; /* nominal-attrbute [x.nominal,lambda.nominal] with lambda.nominal=1.0 */

  /* used in wrapper_*/
  double* f1;
  double* f2;
  /* used for steepest descent method */
  double* gradFx;

  /* return value, if success info == 1 */
  int info;
  int numberOfIterations; /* over the whole simulation time */
  int numberOfFunctionEvaluations; /* over the whole simulation time */
  int maxNumberOfIterations; /* number of Newton steps */

  /* newton algorithm*/
  double* x;
  double* x0;
  double* xStart;
  double* x1;
  double* finit;
  double* fx0;
  double* fJac;
  double* fJacx0;

  /* debug arrays */
  double* debug_fJac;
  double* debug_dx;

  /* homotopy parameters */
  int homotopyMethod;
  double startDirection;
  double  tau;
  double* y0;
  double* y1;
  double* y2;
  double* yt;
  double* dy0;
  double* dy1;
  double* dy2;
  double* hvec;
  double* hJac;
  double* hJacInit;
  double* ones;

  /* linear system */
  int* indRow;
  int* indCol;

  int (*f)         (struct DATA_HOMOTOPY*, double*, double*);
  int (*fJac_f)    (struct DATA_HOMOTOPY*, double*, double*);
  int (*h_function)(struct DATA_HOMOTOPY*, double*, double*);
  int (*hJac_dh)   (struct DATA_HOMOTOPY*, double*, double*);

  DATA* data;
  int sysNumber;
  int eqSystemNumber;
  double timeValue;
  int mixedSystem;

  void* dataHybrid;

} DATA_HOMOTOPY;

/*! \fn allocateHomotopyData
 *  allocate memory for nonlinear system solver
 *  \author bbachmann
 */
int allocateHomotopyData(int size, void** voiddata)
{
  DATA_HOMOTOPY* data = (DATA_HOMOTOPY*) malloc(sizeof(DATA_HOMOTOPY));

  *voiddata = (void*)data;
  assertStreamPrint(NULL, 0 != data, "allocationHomotopyData() failed!");

  data->initialized = 0;
  data->n = size;
  data->m = size + 1;
  data->xtol = 1e-24;
  data->ftol = 1e-24;

  data->error_f = 0;

  data->maxNumberOfIterations = size*100;
  data->numberOfIterations = 0;
  data->numberOfFunctionEvaluations = 0;

  data->resScaling = (double*) calloc(size,sizeof(double));
  data->fvecScaled = (double*) calloc(size,sizeof(double));
  data->hvecScaled = (double*) calloc(size,sizeof(double));
  data->dxScaled = (double*) calloc(size,sizeof(double));

  data->xScaling = (double*) calloc((size+1),sizeof(double));

  data->f1 = (double*) calloc(size,sizeof(double));
  data->f2 = (double*) calloc(size,sizeof(double));
  data->gradFx = (double*) calloc(size,sizeof(double));

  /* damped newton */
  data->x = (double*) calloc(size,sizeof(double));
  data->x0 = (double*) calloc(size,sizeof(double));
  data->xStart = (double*) calloc(size,sizeof(double));
  data->x1 = (double*) calloc(size,sizeof(double));
  data->finit = (double*) calloc(size,sizeof(double));
  data->fx0 = (double*) calloc(size,sizeof(double));
  data->fJac = (double*) calloc((size*(size+1)),sizeof(double));
  data->fJacx0 = (double*) calloc((size*(size+1)),sizeof(double));

  /* debug arrays */
  data->debug_dx = (double*) calloc(size,sizeof(double));
  data->debug_fJac = (double*) calloc((size*(size+1)),sizeof(double));

   /* homotopy */
  data->y0 = (double*) calloc((size+1),sizeof(double));
  data->y1 = (double*) calloc((size+1),sizeof(double));
  data->y2 = (double*) calloc((size+1),sizeof(double));
  data->yt = (double*) calloc((size+1),sizeof(double));
  data->dy0 = (double*) calloc((size+1),sizeof(double));
  data->dy1 = (double*) calloc((size+1),sizeof(double));
  data->dy2 = (double*) calloc((size+1),sizeof(double));
  data->hvec = (double*) calloc(size,sizeof(double));
  data->hJac  = (double*) calloc(size*(size+1),sizeof(double));
  data->hJacInit  = (double*) calloc(size*(size+1),sizeof(double));
  data->ones  = (double*) calloc(size+1,sizeof(double));

  /* linear system */
  data->indRow =(int*) calloc(size,sizeof(int));
  data->indCol =(int*) calloc(size+1,sizeof(int));

  allocateHybrdData(size, &data->dataHybrid);

  assertStreamPrint(NULL, 0 != *voiddata, "allocationHomotopyData() voiddata failed!");
  return 0;
}

/*! \fn freeHomotopyData
 *
 *  free memory for nonlinear system solver
 *  \author bbachmann
 */
int freeHomotopyData(void **voiddata)
{
  DATA_HOMOTOPY* data = (DATA_HOMOTOPY*) *voiddata;

  free(data->resScaling);
  free(data->fvecScaled);
  free(data->hvecScaled);
  free(data->x);
  free(data->debug_dx);
  free(data->finit);
  free(data->f1);
  free(data->f2);
  free(data->gradFx);
  free(data->fJac);
  free(data->fJacx0);
  free(data->debug_fJac);

  /* damped newton */
  free(data->x0);
  free(data->xStart);
  free(data->x1);
  free(data->dxScaled);

  /* homotopy */
  free(data->fx0);
  free(data->hvec);
  free(data->hJac);
  free(data->hJacInit);
  free(data->y0);
  free(data->y1);
  free(data->y2);
  free(data->yt);
  free(data->dy0);
  free(data->dy1);
  free(data->dy2);
  free(data->xScaling);
  free(data->ones);

  /* linear system */
  free(data->indRow);
  free(data->indCol);

  freeHybrdData(&data->dataHybrid);

  return 0;
}

/* Prototypes for debug functions
 *  \author bbachmann
 */

void printUnknowns(int logName, DATA_HOMOTOPY *solverData)
{
  long i;
  int eqSystemNumber = solverData->eqSystemNumber;
  DATA *data = solverData->data;

  if (!ACTIVE_STREAM(logName)) return;
  infoStreamPrint(logName, 1, "nls status");
  infoStreamPrint(logName, 1, "variables");
  messageClose(logName);

  for(i=0; i<solverData->n; i++)
    infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t nom = %16.8g\t\t min = %16.8g\t\t max = %16.8g", i+1,
                    modelInfoGetEquation(&data->modelData.modelDataXml,eqSystemNumber).vars[i],
                    solverData->x[i], solverData->xScaling[i], solverData->minValue[i], solverData->maxValue[i]);
  messageClose(logName);
}

void printNewtonStep(int logName, DATA_HOMOTOPY *solverData)
{
  long i;
  int eqSystemNumber = solverData->eqSystemNumber;
  DATA *data = solverData->data;

  if (!ACTIVE_STREAM(logName)) return;
  infoStreamPrint(logName, 1, "newton step");
  infoStreamPrint(logName, 1, "variables");
  messageClose(logName);

  for(i=0; i<solverData->n; i++)
    infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t step = %16.8g\t\t old = %16.8g", i+1,
                    modelInfoGetEquation(&data->modelData.modelDataXml,eqSystemNumber).vars[i],
                    solverData->x1[i], solverData->dy0[i], solverData->x[i]);
  messageClose(logName);
}

void printHomotopyUnknowns(int logName, DATA_HOMOTOPY *solverData)
{
  long i;
  int eqSystemNumber = solverData->eqSystemNumber;
  DATA *data = solverData->data;

  if (!ACTIVE_STREAM(logName)) return;
  infoStreamPrint(logName, 1, "homotopy status");
  infoStreamPrint(logName, 1, "variables");
  messageClose(logName);

  for(i=0; i<solverData->n; i++)
    infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t nom = %16.8g\t\t min = %16.8g\t\t max = %16.8g", i+1,
                    modelInfoGetEquation(&data->modelData.modelDataXml,eqSystemNumber).vars[i],
                    solverData->y0[i], solverData->xScaling[i], solverData->minValue[i], solverData->maxValue[i]);
  infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t nom = %16.8g", i+1,
                  "LAMBDA",
                  solverData->y0[solverData->n], solverData->xScaling[solverData->n]);
  messageClose(logName);
}

void printHomotopyPredictorStep(int logName, DATA_HOMOTOPY *solverData)
{
  long i;
  int eqSystemNumber = solverData->eqSystemNumber;
  DATA *data = solverData->data;

  if (!ACTIVE_STREAM(logName)) return;
  infoStreamPrint(logName, 1, "predictor status");
  infoStreamPrint(logName, 1, "variables");
  messageClose(logName);

  for(i=0; i<solverData->n; i++)
    infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t dy = %16.8g\t\t old = %16.8g\t\t tau = %16.8g", i+1,
                    modelInfoGetEquation(&data->modelData.modelDataXml,eqSystemNumber).vars[i],
                    solverData->yt[i], solverData->dy0[i], solverData->y0[i], solverData->tau);
  infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t dy = %16.8g\t\t old = %16.8g\t\t tau = %16.8g", i+1,
                  "LAMBDA",
                  solverData->yt[solverData->n], solverData->dy0[i], solverData->y0[i], solverData->tau);
  messageClose(logName);
}

void printHomotopyCorrectorStep(int logName, DATA_HOMOTOPY *solverData)
{
  long i;
  int eqSystemNumber = solverData->eqSystemNumber;
  DATA *data = solverData->data;

  if (!ACTIVE_STREAM(logName)) return;
  infoStreamPrint(logName, 1, "corrector status");
  infoStreamPrint(logName, 1, "variables");
  messageClose(logName);

  for(i=0; i<solverData->n; i++)
    infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t dy = %16.8g\t\t old = %16.8g\t\t tau = %16.8g", i+1,
                    modelInfoGetEquation(&data->modelData.modelDataXml,eqSystemNumber).vars[i],
                    solverData->y1[i], solverData->dy1[i], solverData->yt[i], solverData->tau);
  infoStreamPrint(logName, 0, "[%2ld] %30s  = %16.8g\t\t dy = %16.8g\t\t old = %16.8g\t\t tau = %16.8g", i+1,
                  "LAMBDA",
                  solverData->y1[solverData->n], solverData->dy1[i], solverData->yt[i], solverData->tau);
  messageClose(logName);
}

void debugMatrixPermutedDouble(int logName, char* matrixName, double* matrix, int n, int m, int* indRow, int* indCol)
{
  if(ACTIVE_STREAM(logName))
  {
    int i, j;
    int sparsity = 0;
    char buffer[4096];

    infoStreamPrint(logName, 1, "%s [%dx%d-dim]", matrixName, n, m);
    for(i=0; i<n;i++)
    {
      buffer[0] = 0;
      for(j=0; j<m; j++)
        if (sparsity) {
          if (fabs(matrix[indRow[i] + indCol[j]*(m-1)])<1e-12)
            sprintf(buffer, "%s 0", buffer);
          else
            sprintf(buffer, "%s *", buffer);
        } else {
          sprintf(buffer, "%s%16.8g ", buffer, matrix[indRow[i] + indCol[j]*(m-1)]);
        }
      infoStreamPrint(logName, 0, "%s", buffer);
    }
    messageClose(logName);
  }
}

void debugMatrixDouble(int logName, char* matrixName, double* matrix, int n, int m)
{
  if(ACTIVE_STREAM(logName))
  {
    int i, j;
    int sparsity = 0;
    char buffer[4096];

    infoStreamPrint(logName, 1, "%s [%dx%d-dim]", matrixName, n, m);
    for(i=0; i<n;i++)
    {
      buffer[0] = 0;
      for(j=0; j<m; j++)
        if (sparsity) {
          if (fabs(matrix[i + j*(m-1)])<1e-12)
            sprintf(buffer, "%s 0", buffer);
          else
            sprintf(buffer, "%s *", buffer);
        } else {
          sprintf(buffer, "%s%16.8g ", buffer, matrix[i + j*(m-1)]);
        }
      infoStreamPrint(logName, 0, "%s", buffer);
    }
    messageClose(logName);
  }
}

void debugVectorDouble(int logName, char* vectorName, double* vector, int n)
{
   if(ACTIVE_STREAM(logName))
  {
    int i;
    char buffer[4096];

    infoStreamPrint(logName, 1, "%s [%d-dim]", vectorName, n);
    buffer[0] = 0;
    for(i=0; i<n;i++)
    {
      if (vector[i]<-1e+300)
        sprintf(buffer, "%s -INF ", buffer);
      else if (vector[i]>1e+300)
        sprintf(buffer, "%s +INF ", buffer);
      else
        sprintf(buffer, "%s%16.8g ", buffer, vector[i]);
    }
    infoStreamPrint(logName, 0, "%s", buffer);
    messageClose(logName);
  }
}

void debugVectorInt(int logName, char* vectorName, modelica_boolean* vector, int n)
{
   if(ACTIVE_STREAM(logName))
  {
    int i;
    char buffer[4096];

    infoStreamPrint(logName, 1, "%s [%d-dim]", vectorName, n);
    buffer[0] = 0;
    for(i=0; i<n;i++)
    {
      if (vector[i]<-1e+300)
        sprintf(buffer, "%s -INF ", buffer);
      else if (vector[i]>1e+300)
        sprintf(buffer, "%s +INF ", buffer);
      else
        sprintf(buffer, "%s   %d", buffer, vector[i]);
    }
    infoStreamPrint(logName, 0, "%s", buffer);
    messageClose(logName);
  }
}


void debugString(int logName, char* message)
{
  if(ACTIVE_STREAM(logName))
  {
    infoStreamPrint(logName, 1, "%s", message);
    messageClose(logName);
  }
}

void debugInt(int logName, char* message, int value)
{
  if(ACTIVE_STREAM(logName))
  {
    infoStreamPrint(logName, 1, "%s %d", message, value);
    messageClose(logName);
  }
}

void debugDouble(int logName, char* message, double value)
{
  if(ACTIVE_STREAM(logName))
  {
    infoStreamPrint(logName, 1, "%s %18.10e", message, value);
    messageClose(logName);
  }
}

/* Prototypes for linear algebra functions
 *  \author bbachmann
 */

double vecNorm(int n, double *x)
{
  int i;
  double norm=0.0;
  for (i=0;i<n;i++)
    norm+=x[i]*x[i];
  return sqrt(norm);
}

double vecNorm2(int n, double *x)
{
  int i;
  double norm=0.0;
  for (i=0;i<n;i++)
    norm+=x[i]*x[i];
  return norm;
}

double vecMaxNorm(int n, double *x)
{
  int i;
  double norm=fabs(x[0]);
  for (i=1;i<n;i++)
    if (fabs(x[i])>norm)
       norm=fabs(x[i]);
  return norm;
}

void vecAdd(int n, double *a, double *b, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = a[i] + b[i];
}

void vecAddScal(int n, double *a, double *b, double s, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = a[i] + s*b[i];
}

void vecScalarMult(int n, double *a, double s, double *b)
{
  int i;
  for (i=0;i<n;i++)
    b[i] = s*a[i];
}

void vecLinearComb(int n, double *a, double r, double *b, double s, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = r*a[i] + s*b[i];
}

void vecCopy(int n, double *a, double *b)
{
  memcpy(b, a, n*(sizeof(double)));
}

void vecCopyBool(int n, modelica_boolean *a, modelica_boolean *b)
{
  memcpy(b, a, n*(sizeof(modelica_boolean)));
}

void vecAddInv(int n, double *a, double *b)
{
  int i;
  for (i=0;i<n;i++)
    b[i] = -a[i];
}

void vecDiff(int n, double *a, double *b, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = a[i] - b[i];
}

int isNotEqualVectorInt(int n, modelica_boolean *a, modelica_boolean *b)
{
  int i, isNotEqual = 0;
  for (i=0;i<n;i++)
    isNotEqual += abs(a[i] - b[i]);
  return isNotEqual;
}

void vecMultScaling(int n, double *a, double *b, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = a[i]*fabs(b[i]);
}

void vecDivScaling(int n, double *a, double *b, double *c)
{
  int i;
  for (i=0;i<n;i++)
    c[i] = a[i]/fmax(1.0,fabs(b[i]));
}

void vecNormalize(int n, double *a, double *b)
{
  int i;
  double norm = vecNorm(n,a);
  for (i=0;i<n;i++)
    b[i] = a[i]/norm;
}

void vecConst(int n, double value, double *a)
{
  int i;
  for (i=0;i<n;i++)
    a[i] = value;
}

double vecScalarProd(int n, double *a, double *b)
{
  int i;
  double prod;

  for (i=0,prod=0;i<n;i++)
    prod = prod + a[i]*b[i];

  return prod;
}

/* Matrix has dimension [n x m], vector [m] */
void matVecMult(int n, int m, double *A, double *b, double *c)
{
  int i, j;
  for (i=0;i<n;i++) {
    c[i] = 0.0;
    for (j=0;j<m;j++)
      c[i] += A[i+j*(m-1)]*b[j];
  }
}

/* Matrix has dimension [n x m], vector [m] */
void matVecMultAbs(int n, int m, double *A, double *b, double *c)
{
  int i, j;
  for (i=0;i<n;i++) {
    c[i] = 0.0;
    for (j=0;j<m;j++)
      c[i] += fabs(A[i+j*(m-1)]*b[j]);
  }
}

/* Matrix has dimension [n x (n+1)] */
void matVecMultBB(int n, double *A, double *b, double *c)
{
  int i, j;
  for (i=0;i<n;i++) {
    c[i] = 0.0;
    for (j=0;j<n;j++)
      c[i] += A[i+j*n]*b[j];
  }
}

/* Matrix has dimension [n x (n+1)] */
void matVecMultAbsBB(int n, double *A, double *b, double *c)
{
  int i, j;
  for (i=0;i<n;i++) {
    c[i] = 0.0;
    for (j=0;j<n;j++)
       c[i] += fabs(A[i+j*n]*b[j]);
  }
}

/* Matrix has dimension [n x (n+1)] */
void matAddBB(int n, double* A, double* B, double* C)
{
  int i, j;

  for (i=0;i<n;i++) {
    for (j=0;j<n+1;j++)
      C[i + j*n] = A[i + j*n] + B[i + j*n];
  }
}

/* Matrix has dimension [n x (n+1)] */
void matDiffBB(int n, double* A, double* B, double* C)
{
  int i, j;

  for (i=0;i<n;i++) {
    for (j=0;j<n;j++)
      C[i + j*n] = A[i + j*n] - B[i + j*n];
  }
}

/* Matrix has dimension [n x m] */
void scaleMatrixRows(int n, int m, double *A)
{
  const double delta = sqrt(DBL_EPSILON);
  int i, j;
  double rowMax;
  for (i=0;i<n;i++) {
    rowMax = delta; /* This might be changed to smaller number */
    for (j=0;j<m;j++) {
      if (fabs(A[i+j*(m-1)]) > rowMax) {
         rowMax = fabs(A[i+j*(m-1)]);
      }
    }
    for (j=0;j<m;j++)
      A[i+j*(m-1)] /= rowMax;
  }
}

void swapPointer(double* *p1, double* *p2)
{
  double* help;
  help = *p1;
  *p1 = *p2;
  *p2 = help;
}

/*! \fn getAnalyticalJacobian
 *
 *  function calculates analytical jacobian
 *
 *  \param [ref] [data]
 *  \param [out] [jac]
 *
 *  \author wbraun
 *          bbachmann: introduce scaling factor
 *
 */
int getAnalyticalJacobianHomotopy(DATA_HOMOTOPY* solverData, double* jac)
{
  DATA* data = solverData->data;
  int i,j,k,l,ii;
  NONLINEAR_SYSTEM_DATA* systemData = &(data->simulationInfo.nonlinearSystemData[solverData->sysNumber]);
  const int index = systemData->jacobianIndex;

  memset(jac, 0, (solverData->n)*(solverData->n)*sizeof(double));

  for(i=0; i < data->simulationInfo.analyticJacobians[index].sparsePattern.maxColors; i++)
  {
    /* activate seed variable for the corresponding color */
    for(ii=0; ii < data->simulationInfo.analyticJacobians[index].sizeCols; ii++)
      if(data->simulationInfo.analyticJacobians[index].sparsePattern.colorCols[ii]-1 == i)
        data->simulationInfo.analyticJacobians[index].seedVars[ii] = 1;

    ((systemData->analyticalJacobianColumn))(data);

    for(j = 0; j < data->simulationInfo.analyticJacobians[index].sizeCols; j++)
    {
      if(data->simulationInfo.analyticJacobians[index].seedVars[j] == 1)
      {
        if(j==0)
          ii = 0;
        else
          ii = data->simulationInfo.analyticJacobians[index].sparsePattern.leadindex[j-1];
        while(ii < data->simulationInfo.analyticJacobians[index].sparsePattern.leadindex[j])
        {
          l  = data->simulationInfo.analyticJacobians[index].sparsePattern.index[ii];
          k  = j*data->simulationInfo.analyticJacobians[index].sizeRows + l;
          /* Calculate scaled difference quotient */
          jac[k] = data->simulationInfo.analyticJacobians[index].resultVars[l] * solverData->xScaling[j];
          ii++;
        };
      }
      /* de-activate seed variable for the corresponding color */
      if(data->simulationInfo.analyticJacobians[index].sparsePattern.colorCols[j]-1 == i)
        data->simulationInfo.analyticJacobians[index].seedVars[j] = 0;
    }
  }

  return 0;
}

/*! \fn getNumericalJacobianHomotopy
 *
 *  function calculates a jacobian matrix by
 *  numerical method finite differences
 *  \author bbachmann
 *
*/
static int getNumericalJacobianHomotopy(DATA_HOMOTOPY* solverData, double *x, double *fJac)
{
  const double delta_h = sqrt(DBL_EPSILON*2e1);
  double delta_hh;
  double xsave;

  int i,j,l;

  /* solverData->f1 must be set outside this function based on x */
  for(i = 0; i < solverData->n; i++) {
    xsave = x[i];
    delta_hh = delta_h * (fabs(xsave) + 1.0);
    if ((xsave + delta_hh >=  solverData->maxValue[i]))
      delta_hh *= -1;
    x[i] += delta_hh;
    /* Calculate scaled difference quotient */
    delta_hh = 1. / delta_hh * solverData->xScaling[i];

    solverData->f(solverData, x, solverData->f2);

    for(j = 0; j < solverData->n; j++) {
      l = i * solverData->n + j;
      fJac[l] = (solverData->f2[j] - solverData->f1[j]) * delta_hh;
    }
    x[i] = xsave;
  }
  return 0;
}

/*! \fn wrapper_fvec_hybrd for the residual Function
 *   tensolve calls for the subroutine fcn(n, x, fvec, iflag, data)
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec(DATA_HOMOTOPY* solverData, double* x, double* f)
{
  int iflag = 0;

  /*TODO: change input to residualFunc from data to systemData */
  (solverData->data)->simulationInfo.nonlinearSystemData[solverData->sysNumber].residualFunc(solverData->data, x, f, &iflag);
  solverData->numberOfFunctionEvaluations++;

  return 0;
}

/*! \fn wrapper_fvec_hybrd for the residual Function
 *   tensolve calls for the subroutine fcn(n, x, fvec, iflag, data)
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec_der(DATA_HOMOTOPY* solverData, double* x, double* fJac)
{
  int i;
  int jacobianIndex = (&(solverData->data->simulationInfo.nonlinearSystemData[solverData->sysNumber]))->jacobianIndex;

  /* calculate jacobian */
  if(jacobianIndex != -1)
  {
    /* !!!!!!!!!!! Be sure that actual x is used !!!!!!!!!!! */
    getAnalyticalJacobianHomotopy(solverData, fJac);
  }
  else
  {
    getNumericalJacobianHomotopy(solverData, x, fJac);
  }

  if(ACTIVE_STREAM(LOG_NLS_JAC_TEST))
  {
    int n = solverData->n;

    /* debugMatrixDouble(LOG_NLS_JAC_TEST,"analytical jacobian:",fJac, n, n+1); */
    getNumericalJacobianHomotopy(solverData, x, solverData->debug_fJac);
    /* debugMatrixDouble(LOG_NLS_JAC_TEST,"numerical jacobian:",solverData->debug_fJac, n, n+1); */
    matDiffBB(n, fJac, solverData->debug_fJac, solverData->debug_fJac);
    /* debugMatrixDouble(LOG_NLS_JAC_TEST,"Difference of jacobians:",solverData->debug_fJac, n, n+1); */
    debugDouble(LOG_NLS_JAC_TEST,"error between analytical and numerical jacobian = ", vecMaxNorm(n*n, solverData->debug_fJac));
    vecDivScaling(n*(n+1), solverData->debug_fJac , fJac, solverData->debug_fJac);
    debugDouble(LOG_NLS_JAC_TEST,"relative error between analytical and numerical jacobian = ", vecMaxNorm(n*n, solverData->debug_fJac));
    messageClose(LOG_NLS_JAC_TEST);
  }

  return 0;
}

/*! \fn wrapper_fvec_homotopy for the residual Function
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec_homotopy_newton(DATA_HOMOTOPY* solverData, double* x, double* h)
{
  int i;
  int n = solverData->n;

  /*  Newton homotopy */
  wrapper_fvec(solverData, x, solverData->f1);
  vecAddScal(solverData->n, solverData->f1, solverData->fx0, - (1-x[n]), h);

  return 0;
}

/*! \fn wrapper_fvec_homotopy_der for the residual Function
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec_homotopy_newton_der(DATA_HOMOTOPY* solverData, double* x, double* hJac)
{
  int i, j;
  int n = solverData->n;

  /* Newton homotopy */
  wrapper_fvec_der(solverData, x, hJac);

  /* add f(x0) as the last column of the Jacobian*/
  vecCopy(n, solverData->fx0, hJac + n*n);

  return 0;
}

/*! \fn wrapper_fvec_homotopy for the residual Function
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec_homotopy_fixpoint(DATA_HOMOTOPY* solverData, double* x, double* h)
{
  int i;
  int n = solverData->n;

  /* Fixpoint homotopy */
  wrapper_fvec(solverData, x, solverData->f1);
  for (i=0; i<n; i++){
    h[i] = x[n]*solverData->f1[i] + (1-x[n]) * (x[i]-solverData->x0[i]);
  }

  return 0;
}

/*! \fn wrapper_fvec_homotopy_der for the residual Function
 *
 *  \author bbachmann
 *
 */
static int wrapper_fvec_homotopy_fixpoint_der(DATA_HOMOTOPY* solverData, double* x, double* hJac)
{
  int i, j;
  int n = solverData->n;

  /* Fixpoint homotopy */
  wrapper_fvec_der(solverData, x, hJac);
  for (i=0; i<n; i++){
    for (j=0; j<n; j++) {
      hJac[i+ j * n] = x[n]*hJac[i+ j * n];
    }
    hJac[i+ i * n] = hJac[i+ i * n] + (1-x[n]);
    hJac[i+ n * n] = solverData->f1[i]-(x[i] - solverData->x0[i]);
  }
  return 0;
}

/*! \fn getIndicesOfPivotElement for calculating pivot element
 *
 *  \author bbachmann
 *
 */
 void getIndicesOfPivotElement(int *n, int *m, int *l, double* A, int *indRow, int *indCol, int *pRow, int *pCol, double *absMax)
{
  int i, j;

  *absMax = fabs(A[indRow[*l] + indCol[*l]* *n]);
  *pCol = *l;
  *pRow = *l;
  for (i = *l; i < *n; i++) {
   for (j = *l; j < *m; j++) {
      if (fabs(A[indRow[i] + indCol[j]* *n]) > *absMax) {
        *absMax = fabs(A[indRow[i] + indCol[j]* *n]);
        *pCol = j;
        *pRow = i;
      }
    }
  }
}

/*! \fn solveSystemWithTotalPivotSearch for solution of overdetermined linear system
 *  used for the homotopy solver, for calculating the direction
 *  used for the newton solver, for calculating the Newton step
 *
 *  \author bbachmann
 *
 */
int solveSystemWithTotalPivotSearch(int n, double* x, double* A, int* indRow, int* indCol, int *pos, int *rank)
{
   int i, k, j, l, m=n+1, nrsh=1, singular=0, nPivot=n;
   int pCol, pRow;
   double hValue;
   double hInt;
   double absMax;
   int r,s;
   double *res;

   debugMatrixDouble(LOG_NLS_JAC,"Linear System Matrix [Jac res]:",A, n, m);

   /* assume full rank of matrix [n x (n+1)] */
   *rank = n;

   for (i=0; i<n; i++) {
      indRow[i] = i;
   }
   for (i=0; i<m; i++) {
      indCol[i] = i;
   }
   if (*pos>=0) {
     indCol[n] = *pos;
     indCol[*pos] = n;
   } else {
     nPivot = n+1;
   }

   for (i = 0; i < n; i++) {
    getIndicesOfPivotElement(&n, &nPivot, &i, A, indRow, indCol, &pRow, &pCol, &absMax);
    if (absMax<DBL_EPSILON) {
      *rank = i;
      warningStreamPrint(LOG_NLS, 0, "Matrix singular!");
      debugInt(LOG_NLS,"rank = ", *rank);
      debugInt(LOG_NLS,"position = ", *pos);
      break;
    }
    /* swap row indices */
    if (pRow!=i) {
      hInt = indRow[i];
      indRow[i] = indRow[pRow];
      indRow[pRow] = hInt;
    }
    /* swap column indices */
    if (pCol!=i) {
      hInt = indCol[i];
      indCol[i] = indCol[pCol];
      indCol[pCol] = hInt;
    }

    /* Gauss elimination of row indRow[i] */
    for (k=i+1; k<n; k++) {
      hValue = -A[indRow[k] + indCol[i]*n]/A[indRow[i] + indCol[i]*n];
      for (j=i+1; j<m; j++) {
        A[indRow[k] + indCol[j]*n] = A[indRow[k] + indCol[j]*n] + hValue*A[indRow[i] + indCol[j]*n];
      }
      A[indRow[k] + indCol[i]*n] = 0;
    }
  }

  debugMatrixPermutedDouble(LOG_NLS_JAC,"Linear System Matrix [Jac res] after decomposition",A, n, m, indRow, indCol);
  /* Solve even singular matrices !!! */
  for (i=n-1;i>=0; i--) {
    if (i>=*rank) {
      /* this criteria should be evaluated and may be improved in future */
      if (fabs(A[indRow[i] + indCol[n]*n])>1e-12) {
        warningStreamPrint(LOG_NLS, 0, "under-determined linear system not solvable!");
        return -1;
      } else {
        x[indCol[i]] = 0.0;
      }
    } else {
      x[indCol[i]] = -A[indRow[i] + indCol[n]*n];
      for (j=n-1; j>i; j--) {
        x[indCol[i]] = x[indCol[i]] - A[indRow[i] + indCol[j]*n]*x[indCol[j]];
      }
      x[indCol[i]]=x[indCol[i]]/A[indRow[i] + indCol[i]*n];
    }
  }
  x[indCol[n]]=1.0;

  /* Return position of largest value (1.0) */
  if (*pos<0) {
    *pos=indCol[n];
  }

  /* Debugging error of linear system */
  if(ACTIVE_STREAM(LOG_NLS_JAC))
  {
    res = (double*) calloc(n,sizeof(double));
    debugVectorDouble(LOG_NLS_JAC,"solution:", x, m);
    matVecMult(n, m, A, x, res);
    debugVectorDouble(LOG_NLS_JAC,"test solution:", res, n);
    debugDouble(LOG_NLS_JAC,"error of linear system = ", vecNorm(n, res));
    free(res);
    messageClose(LOG_NLS_JAC);
  }

  return 0;
}
/*! \fn solve system with damped Newton-Raphson
 *
 *  \author bbachmann
 *
 */
static int newtonAlgorithm(DATA_HOMOTOPY* solverData, double* x)
{
  int numberOfIterations = 0 ,i, j, n=solverData->n, m=solverData->m;
  int  pos = solverData->n, rank;
  double error_f, error_f1, error_f2,error_f_scaled, delta_x, delta_x_scaled, grad_f1, grad_f;
  int numberOfSmallSteps = 0;
  double error_f_old = 1e100;
  int countNegativeSteps = 0;
  double lambda;
  double lambda1, lambda2;
  double lambdaMin = 1e-4;
  double a2, a3, rhs1, rhs2, D;
  double alpha = 1e-1;
  int firstrun;

  int assert = 1;
  threadData_t *threadData = solverData->data->threadData;
  NONLINEAR_SYSTEM_DATA* nonlinsys = &(solverData->data->simulationInfo.nonlinearSystemData[solverData->data->simulationInfo.currentNonlinearSystemIndex]);

  /* debug information */
  debugString(LOG_NLS_V, "******************************************************");
  debugInt(LOG_NLS_V, "NEWTON SOLVER STARTED! equation number: ",solverData->eqSystemNumber);
  debugInt(LOG_NLS_V, "maximum number of function evaluation: ", solverData->maxNumberOfIterations);
  printUnknowns(LOG_NLS, solverData);

  /* set default solver message */
  solverData->info = 0;

  /* calculated error of function values */
  error_f = vecNorm2(solverData->n, solverData->f1);
  error_f_scaled = error_f;

  while(1)
  {
    numberOfIterations++;
    /* debug information */
    debugInt(LOG_NLS_V, "Iteration:", numberOfIterations);

    /* solve jacobian and function value (both stored in hJac, last column is fvec), side effects: jacobian matrix is changed */
    if ((numberOfIterations>1) && (solveSystemWithTotalPivotSearch(solverData->n, solverData->dy0, solverData->fJac, solverData->indRow, solverData->indCol, &pos, &rank) != 0))
    {
      /* report solver abortion */
      solverData->info=-1;
      /* debug information */
      debugString(LOG_NLS_V, "NEWTON SOLVER DID ---NOT--- CONVERGE TO A SOLUTION!!!");
      debugString(LOG_NLS_V, "******************************************************");
      assert = 0;
      break;
    }
    else
    {
      /* Scaling back to original variables */
      vecMultScaling(solverData->m, solverData->dy0, solverData->xScaling, solverData->dy0);
      /* try full Newton step */
      vecAdd(solverData->n, x, solverData->dy0, solverData->x1);
      printNewtonStep(LOG_NLS_V, solverData);

      /* Damping strategy, performance is very sensitive on the value of lambda */
      lambda1 = 1.0;
      assert = 1;
      firstrun = 1;
      while (assert && (lambda1 > lambdaMin))
      {
        if (!firstrun){
          lambda1 *= 0.655;
          vecAddScal(solverData->n, x, solverData->dy0, lambda1, solverData->x1);
          assert = 1;
        }
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
        solverData->f(solverData, solverData->x1, solverData->f1);
        assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
        firstrun = 0;
        if (assert){
          debugDouble(LOG_NLS_V,"Assert of Newton step: lambda1 =", lambda1);
        }
      }

      if (lambda1 < lambdaMin)
      {
        debugDouble(LOG_NLS,"UPS! MUST HANDLE A PROBLEM (Newton method), time : ", solverData->timeValue);
        solverData->info = -1;
        break;
      }

      /* Damping (see Numerical Recipes) */
      /* calculate gradient of quadratic function for damping strategy */
      grad_f = -2.0*error_f;
      error_f1 = vecNorm2(solverData->n, solverData->f1);
      debugDouble(LOG_NLS_V,"Need to damp, grad_f = ", grad_f);
      debugDouble(LOG_NLS_V,"Need to damp, error_f = ", error_f);

      debugDouble(LOG_NLS_V,"Need to damp this!! lambda1 = ", lambda1);
      debugDouble(LOG_NLS_V,"Need to damp, error_f1 = ", error_f1);

      debugDouble(LOG_NLS_V,"Need to damp, forced error = ", error_f + alpha*lambda1*grad_f);
      if ((error_f1 > error_f + alpha*lambda1*grad_f) && (error_f > 1e-12) && (error_f_scaled > 1e-12))
      {
        lambda2 = fmax(-lambda1*lambda1*grad_f/(2*(error_f1-error_f-lambda1*grad_f)),lambdaMin);
        debugDouble(LOG_NLS_V,"Need to damp this!! lambda2 = ", lambda2);
        vecAddScal(solverData->n, x, solverData->dy0, lambda2, solverData->x1);
        assert= 1;
#ifndef OMC_EMCC
        MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
        solverData->f(solverData, solverData->x1, solverData->f1);
        error_f2 = vecNorm2(solverData->n, solverData->f1);
        debugDouble(LOG_NLS_V,"Need to damp, error_f2 = ", error_f2);
        assert = 0;
#ifndef OMC_EMCC
        MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
        if (assert)
        {
          debugDouble(LOG_NLS,"UPS! MUST HANDLE A PROBLEM (Newton method), time : ", solverData->timeValue);
          solverData->info = -1;
          break;
        }
        if ((error_f1 > error_f + alpha*lambda2*grad_f) && (error_f > 1e-12) && (error_f_scaled > 1e-12))
        {
          rhs1 = error_f1 - grad_f*lambda1 - error_f;
          rhs2 = error_f2 - grad_f*lambda2 - error_f;
          a3 = (rhs1/(lambda1*lambda1) - rhs2/(lambda2*lambda2))/(lambda1 - lambda2);
          a2 = (-lambda2*rhs1/(lambda1*lambda1) + lambda1*rhs2/(lambda2*lambda2))/(lambda1 - lambda2);
          if (a3==0.0)
            lambda = -grad_f/(2.0*a2);
          else
          {
            D = a2*a2 - 3.0*a3*grad_f;
            if (D <= 0.0)
              lambda = 0.5*lambda1;
            else
              if (a2 <= 0.0)
                lambda = (-a2+sqrt(D))/(3.0*a3);
              else
                lambda = -grad_f/(a2+sqrt(D));
          }
          lambda = fmax(lambda, lambdaMin);
          debugDouble(LOG_NLS_V,"Need to damp this!! lambda = ", lambda);
          vecAddScal(solverData->n, x, solverData->dy0, lambda, solverData->x1);
          assert= 1;
#ifndef OMC_EMCC
          MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
          solverData->f(solverData, solverData->x1, solverData->f1);
          error_f1 = vecNorm2(solverData->n, solverData->f1);
          debugDouble(LOG_NLS_V,"Need to damp, error_f1 = ", error_f1);
          assert = 0;
#ifndef OMC_EMCC
          MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
          if (assert)
          {
            debugDouble(LOG_NLS,"UPS! MUST HANDLE A PROBLEM (Newton method), time : ", solverData->timeValue);
            solverData->info = -1;
            break;
          }
        }
      }else{
        lambda = lambda1;
      }
    }
    /* updating x, fvec, error_f */
    /* event. swapPointer(&x, &(solverData->x1)); */
    vecCopy(solverData->n, solverData->x1, x);

    /* Calculate different error measurements */
    vecDivScaling(solverData->n, solverData->f1, solverData->resScaling, solverData->fvecScaled);
    debugVectorDouble(LOG_NLS_V,"function values:",solverData->f1, n);
    debugVectorDouble(LOG_NLS_V,"scaled function values:",solverData->fvecScaled, n);
    vecDivScaling(solverData->n, solverData->dy0, solverData->xScaling, solverData->dxScaled);
    delta_x        = vecNorm2(solverData->n, solverData->dy0);
    delta_x_scaled = vecNorm2(solverData->n, solverData->dxScaled);
    error_f        = vecNorm2(solverData->n, solverData->f1);
    error_f_scaled = vecNorm2(solverData->n, solverData->fvecScaled);


    /* debug information */
    debugString(LOG_NLS_V, "error measurements:");
    debugDouble(LOG_NLS_V, "delta_x        =", delta_x);
    debugDouble(LOG_NLS_V, "delta_x_scaled =", delta_x_scaled);
    debugDouble(LOG_NLS_V, "eps_x          =", solverData->xtol);
    debugDouble(LOG_NLS_V, "error_f        =", error_f);
    debugDouble(LOG_NLS_V, "error_f_scaled =", error_f_scaled);
    debugDouble(LOG_NLS_V, "eps_f          =", solverData->ftol);

    countNegativeSteps += (error_f > 10*error_f_old);
    error_f_old = error_f;

    if (solverData->data->simulationInfo.nlsCsvInfomation){
      print_csvLineIterStats(((struct csvStats*) nonlinsys->csvData)->iterStats,
                             nonlinsys->size,
                             nonlinsys->numberOfCall+1,
                             numberOfIterations,
                             solverData->x,
                             solverData->f1,
                             delta_x,
                             delta_x_scaled,
                             error_f,
                             error_f_scaled,
                             lambda
      );
    }

    if ((error_f_scaled < 1e-30*error_f) || countNegativeSteps > 20)
    {
      debugInt(LOG_NLS_V,"UPS! Something happened, NegativeSteps = ", countNegativeSteps);
      solverData->info = -1;
      break;
    }

    /* solution found */
    if (((error_f < solverData->ftol) || (error_f_scaled < solverData->ftol)) && ((delta_x_scaled < solverData->xtol) || (delta_x < solverData->xtol)))
    {
      solverData->info = 1;

      /* debug information */
      debugString(LOG_NLS_V, "NEWTON SOLVER DID CONVERGE TO A SOLUTION!!!");
      printUnknowns(LOG_NLS_V, solverData);
      debugString(LOG_NLS_V, "******************************************************");

      /* update statistics */
      solverData->numberOfIterations += numberOfIterations;
      solverData->error_f = error_f;

      break;
    }

    /* check if maximum iteration is reached */
    if (numberOfIterations > solverData->maxNumberOfIterations)
    {
      solverData->info = -1;
      warningStreamPrint(LOG_NLS_V, 0, "Warning: maximal number of iteration reached but no root found");
      /* debug information */
      debugString(LOG_NLS_V, "NEWTON SOLVER DID ---NOT--- CONVERGE TO A SOLUTION!!!");
      debugString(LOG_NLS_V, "******************************************************");

      /* update statistics */
      solverData->numberOfIterations += numberOfIterations;
      break;
    }

    numberOfSmallSteps += (delta_x < solverData->xtol*1e4) ||  (delta_x_scaled < solverData->xtol*1e4);
    /* check changes in unknown vector */
    if ((delta_x < solverData->xtol) ||  (delta_x_scaled < solverData->xtol) || (numberOfSmallSteps > 20))
    {
      if ((error_f < solverData->ftol*1e6) || (error_f_scaled < solverData->ftol*1e6))
      {
        solverData->info = 1;

        /* debug information */
        debugString(LOG_NLS_V, "NEWTON SOLVER DID CONVERGE TO A SOLUTION WITH LESS ACCURACY!!!");
        printUnknowns(LOG_NLS_V, solverData);
        debugString(LOG_NLS_V, "******************************************************");
        solverData->error_f = error_f;

      } else
      {
        solverData->info = -1;
        debugString(LOG_NLS_V, "Warning: newton solver gets stuck!!!");
        /* debug information */
        debugString(LOG_NLS_V, "NEWTON SOLVER DID ---NOT--- CONVERGE TO A SOLUTION!!!");
        debugString(LOG_NLS_V, "******************************************************");
      }
      /* update statistics */
      solverData->numberOfIterations += numberOfIterations;
      break;
    }

    assert = 1;
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
    /* calculate jacobian and function values (both stored in fJac, last column is fvec)*/
    solverData->fJac_f(solverData, x, solverData->fJac);
    assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
    if (assert)
    {
      /* report solver abortion */
      solverData->info=-1;
      debugString(LOG_NLS_V,"UPS! assert when calculating Jacobian!!!");
      break;
    }
    vecCopy(n, solverData->f1, solverData->fJac + n*n);
    /* calculate scaling factor of residuals */
    matVecMultAbsBB(solverData->n, solverData->fJac, solverData->ones, solverData->resScaling);
    debugVectorDouble(LOG_NLS_JAC, "residuum scaling:", solverData->resScaling, solverData->n);
    scaleMatrixRows(solverData->n, solverData->m, solverData->fJac);
  }
  return 0;
}

/*! \fn solve system with homotopy method
 *
 *  \author bbachmann
 */
static int homotopyAlgorithm(DATA_HOMOTOPY* solverData, double *x)
{
  int i, j;
  double xerror = -1, xerror_scaled = -1;
  double error_h, error_h_scaled, delta_x, delta_x_scaled;
  int success = 0;
  int nfunc_evals = 0;
  int continuous = 1;
  double local_tol = solverData->ftol;
  double vecScalarProduct;

  int giveUp = 0;
  int retries = 0;
  int retries2 = 0;
  int iflag = 1;
  int pos, rank;
  int iter = 0;
  int maxiter = 20;
  int numSteps = 0;
  int stepAccept = 0;
  int runHomotopy = 0;
  double bend = 0;
  double sProd, detJac;
  double tau = 0.2, tauMax = 10.0, tauMin = 1e-4, hEps = 1e-3, adaptBend = 0.05;
  int m = solverData->m;
  int n = solverData->n;
  int initialStep = 1;

  int assert = 1;
  threadData_t *threadData = solverData->data->threadData;

  /* Initialize vector dy2 using chosen startDirection */
  /* set start vector, lambda = 0.0 */
  vecCopy(solverData->n, x, solverData->y0);
  solverData->y0[solverData->n] = 0.0;

  vecConst(solverData->n, 0.0, solverData->dy2);
  solverData->dy2[solverData->n]= solverData->startDirection;
  printHomotopyUnknowns(LOG_NLS, solverData);
  assert = 1;
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
    solverData->h_function(solverData, solverData->y0, solverData->hvec);
    assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
  /* start iteration; stop, if lambda = solverData->y0[solverData->n] == 1 */
  while (solverData->y0[solverData->n]<1)
  {
    /* Break loop, iff algorithm gets stuck or lambda accelerates to the wrong direction */
    if (iter>10)
    {
      debugInt(LOG_NLS_HOMOTOPY, "Homotopy Algorithm did not converge: iter = ", iter);
      debugString(LOG_NLS_HOMOTOPY, "======================================================");
      return -1;
    }
    if (solverData->y0[solverData->n]<(-1))
    {
      debugDouble(LOG_NLS_HOMOTOPY, "Homotopy Algorithm did not converge: lambda = ", solverData->y0[solverData->n]);
      debugString(LOG_NLS_HOMOTOPY, "======================================================");
      return -1;
    }
    if (numSteps >= solverData->maxNumberOfIterations)
    {
      debugInt(LOG_NLS_HOMOTOPY, "Homotopy Algorithm did not converge: numSteps = ", numSteps);
      debugString(LOG_NLS_HOMOTOPY, "======================================================");
      return -1;
    }

    stepAccept = 0;

    /* If a step succeeded, calculate the homotopy function and corresponding jacobian */
    if (iter==0)
    {
    /* Handle asserts of function calls, mainly necessary for fluid stuff */
      assert = 1;
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
      solverData->hJac_dh(solverData, solverData->y0, solverData->hJac);
      scaleMatrixRows(solverData->n, solverData->m, solverData->hJac);
      assert = 0;
      pos = -1; /* stable solution algorithm for solving a generalized over-determined linear system */
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif

      if (assert || (solveSystemWithTotalPivotSearch(solverData->n, solverData->dy0, solverData->hJac, solverData->indRow, solverData->indCol, &pos, &rank) != 0))
      {
        /* report solver abortion */
        solverData->info=-1;
        /* debug information */
        if (assert)
          debugString(LOG_NLS_HOMOTOPY, "Assert, when calculating Jacobian!");
        else
          debugString(LOG_NLS_HOMOTOPY, "System singular and not solvable!");
        debugString(LOG_NLS_HOMOTOPY, "Homotopy Algorithm did not converge");
        debugString(LOG_NLS_HOMOTOPY, "======================================================");
        /* update statistics */
        return -1;
      }
      vecMultScaling(solverData->m, solverData->dy0, solverData->xScaling, solverData->dy0);

      /* Correct search direction, depending on the last direction (angle < 90 degree) */
      vecScalarProduct = vecScalarProd(solverData->m,solverData->dy0,solverData->dy2);
      debugDouble(LOG_NLS_HOMOTOPY,"scalar product ", vecScalarProduct);
      if (vecScalarProduct<0 || ((fabs(vecScalarProduct)<DBL_EPSILON) && (solverData->startDirection == -1) && initialStep))
      {
        debugInt(LOG_NLS_HOMOTOPY,"initialStep = ", initialStep);
        debugInt(LOG_NLS_HOMOTOPY,"solverData->startDirection = ", solverData->startDirection);
        debugVectorDouble(LOG_NLS_HOMOTOPY,"step:",solverData->dy0, m);
        vecAddInv(solverData->m, solverData->dy0, solverData->dy0);
        debugVectorDouble(LOG_NLS_HOMOTOPY,"corrected step:",solverData->dy0, m);
      }
      /* adapt tau, if lambda + tau*delta_lambda > 1 */
      if (fabs(solverData->dy0[solverData->n])>1e-8)
      {
        tau = fmin(tau,(1-solverData->y0[solverData->n])/fabs(solverData->dy0[solverData->n]));
      }
    }

    assert = 1;
    while (assert && (tau > tauMin))
    {
      /* do update and store approximated vector in yt */
      vecAddScal(solverData->m, solverData->y0, solverData->dy0, tau,  solverData->y1);

      /* update function value */
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
      solverData->h_function(solverData, solverData->y1, solverData->hvec);
      assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
     if (assert)
       tau = tau/2;
    }
    if (assert)
    {
        /* report solver abortion */
        solverData->info=-1;
        /* debug information */
        debugString(LOG_NLS_HOMOTOPY, "Assert, when calculating function value!");
        debugString(LOG_NLS_HOMOTOPY, "Homotopy Algorithm did not converge");
        debugString(LOG_NLS_HOMOTOPY, "======================================================");
        /* update statistics */
        return -1;
    }
    vecCopy(solverData->m, solverData->y1, solverData->y2);
    vecCopy(solverData->m, solverData->y1, solverData->yt);
    vecCopy(solverData->n, solverData->hvec, solverData->hvecScaled);

    solverData->tau = tau;
    printHomotopyPredictorStep(LOG_NLS_HOMOTOPY, solverData);
    /* Corrector step: Newton iteration! */
    for(j=0;j<maxiter;j++)
    {
      if (vecNorm(solverData->n, solverData->hvec)<hEps || vecNorm(solverData->n, solverData->hvecScaled)<hEps)
      {
        stepAccept = 1;
        break;
      }
      assert = 1;
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
      /* calculate homotopy function and corresponding jacobian */
      solverData->hJac_dh(solverData, solverData->y1, solverData->hJac);
      assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
      if (assert)
      {
          stepAccept = 0;
          break;
      }
      matVecMultAbs(solverData->n, solverData->m, solverData->hJac, solverData->ones, solverData->resScaling);
      debugVectorDouble(LOG_NLS_HOMOTOPY, "residuum scaling of function h:", solverData->resScaling, solverData->n);

      /* copy vector h to column "pos" of the jacobian */
      vecCopy(solverData->n, solverData->hvec, solverData->hJac + pos*solverData->n);
      scaleMatrixRows(solverData->n, solverData->m, solverData->hJac);
      if (solveSystemWithTotalPivotSearch(solverData->n, solverData->dy1, solverData->hJac, solverData->indRow, solverData->indCol, &pos, &rank) != 0)
      {
        stepAccept = 0;
        break;
      }
      /* Scaling back to original variables */
      vecMultScaling(solverData->m, solverData->dy1, solverData->xScaling, solverData->dy1);

      solverData->dy1[pos] = 0.0;
      vecAdd(solverData->m, solverData->y1, solverData->dy1, solverData->y2);
      vecCopy(solverData->m, solverData->y2, solverData->y1);
      assert = 1;
#ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
#endif
      solverData->h_function(solverData, solverData->y1, solverData->hvec);
      assert = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
#endif
      if (assert)
      {
          stepAccept = 0;
          break;
      }
      /* Calculate different error measurements */
      vecDivScaling(solverData->n, solverData->hvec, solverData->resScaling, solverData->hvecScaled);

      delta_x        = vecNorm(solverData->m, solverData->dy1);
      error_h        = vecNorm(solverData->n, solverData->hvec);
      error_h_scaled = vecNorm(solverData->n, solverData->hvecScaled);


      /* debug information
      debugVectorDouble(LOG_NLS_HOMOTOPY,"function values:",solverData->hvec, n);
      debugVectorDouble(LOG_NLS_HOMOTOPY,"scaled function values:",solverData->hvecScaled, n);

      debugString(LOG_NLS_HOMOTOPY, "error measurements:");
      debugDouble(LOG_NLS_HOMOTOPY, "delta_x        =", delta_x);
      debugDouble(LOG_NLS_HOMOTOPY, "error_h        =", error_h);
      debugDouble(LOG_NLS_HOMOTOPY, "error_h_scaled =", error_h_scaled);
      debugDouble(LOG_NLS_HOMOTOPY, "hEps           =", hEps);
      */
    }
    if (!assert)
    {
      vecDiff(solverData->m, solverData->y1, solverData->yt, solverData->dy1);
      vecDiff(solverData->m, solverData->yt, solverData->y0, solverData->dy2);
      printHomotopyCorrectorStep(LOG_NLS_HOMOTOPY, solverData);
      bend = vecNorm(solverData->m,solverData->dy1)/vecNorm(solverData->m,solverData->dy2);
    }
    if ((bend > adaptBend) ||   !stepAccept)
    {
      if (bend<DBL_EPSILON)
      {
        /* debug information */
        debugString(LOG_NLS_HOMOTOPY, "\nINCREMENT ZERO: Homotopy Algorithm did not converge\n");
        debugString(LOG_NLS_HOMOTOPY, "======================================================");
        /* update statistics */
        return -1;
      }
      tau = fmax(tauMin,tau/10.0);
      debugDouble(LOG_NLS_HOMOTOPY, "bend/adaptBend  =", bend/adaptBend);
      debugDouble(LOG_NLS_HOMOTOPY, "--- decreasing step size tau =", tau);
      iter++;
    } else
    {
      initialStep = 0;
      iter = 0;
      numSteps++;
      if (bend < adaptBend/10.0)
      {
        tau = fmin(tauMax, tau*2);
        debugDouble(LOG_NLS_HOMOTOPY, "+++ increasing step size, tau =", tau);
      }
      vecCopy(solverData->m, solverData->y1, solverData->y0);
      vecCopy(solverData->m, solverData->dy0, solverData->dy2);
      debugString(LOG_NLS_HOMOTOPY, "======================================================");
      printHomotopyUnknowns(LOG_NLS_HOMOTOPY, solverData);
    }
  }
  /* copy solution back to vector x */
  vecCopy(solverData->n, solverData->y1, x);

  debugString(LOG_NLS_HOMOTOPY, "HOMOTOPY ALGORITHM SUCCEEDED");
  debugString(LOG_NLS_HOMOTOPY, "======================================================");
  solverData->info = 1;

  return 0;
}

/*! \fn solve non-linear system with a damped Newton method combined with a homotopy approach

 *
 *  \param [in]  [data]
*                [sysNumber] index of the corresponding non-linear system
 *
 *  \author bbachmann
 */
int solveHomotopy(DATA *data, int sysNumber)
{
  NONLINEAR_SYSTEM_DATA* systemData = &(data->simulationInfo.nonlinearSystemData[sysNumber]);
  DATA_HOMOTOPY* solverData = (DATA_HOMOTOPY*)(systemData->solverData);
  DATA_HYBRD* solverDataHybrid;
  threadData_t *threadData = data->threadData;

  /*
   * Get non-linear equation system
   */
  int eqSystemNumber = systemData->equationIndex;
  int homotopySupport = systemData->homotopySupport;
  int mixedSystem = systemData->mixedSystem;

  int i, j;
  int success = 0;
  int nfunc_evals = 0;
  int continuous = 1;
  double local_tol = solverData->ftol;
  double lambda;
  double error_f, error_f1;

  int assert = 1;
  int giveUp = 0;
  int alreadyTested = 0;
  int iflag = 1;
  int pos;
  int rank;
  int iter;
  int maxiter = 10;
  int tries = 0;
  /* Modelica homotopy operator could be used!! */
  int runHomotopy = 0;
  int skipNewton = 0;
  int numberOfFunctionEvaluationsOld = solverData->numberOfFunctionEvaluations;

  modelica_boolean* relationsPreBackup;
  relationsPreBackup = (modelica_boolean*) malloc(data->modelData.nRelations*sizeof(modelica_boolean));

  solverData->f = wrapper_fvec;
  solverData->fJac_f = wrapper_fvec_der;

  solverData->data = data;
  solverData->sysNumber = sysNumber;
  solverData->eqSystemNumber = systemData->equationIndex;
  solverData->mixedSystem = mixedSystem;
  solverData->timeValue = data->localData[0]->timeValue;
  solverData->minValue = systemData->min;
  solverData->maxValue = systemData->max;

  vecConst(solverData->m,1.0,solverData->ones);

  debugString(LOG_NLS_V, "------------------------------------------------------");
  debugString(LOG_NLS_V, "SOLVING NON-LINEAR SYSTEM USING HOMOTOPY SOLVER");
  debugInt(LOG_NLS_V, "EQUATION NUMBER:", eqSystemNumber);
  debugDouble(LOG_NLS_V, "TIME:", solverData->timeValue);
  debugInt(LOG_NLS_V,   "number of function calls (so far!): ",numberOfFunctionEvaluationsOld);

  /* set x vector */
  if(data->simulationInfo.discreteCall)
  {
    vecCopy(solverData->n, systemData->nlsx, solverData->xStart);
    debugVectorDouble(LOG_NLS_V,"System values", solverData->xStart, solverData->n);
  } else
  {
    vecCopy(solverData->n, systemData->nlsxExtrapolation, solverData->xStart);
    debugVectorDouble(LOG_NLS_V,"System extrapolation", solverData->xStart, solverData->n);
  }
  vecCopy(solverData->n, solverData->xStart, solverData->x0);
  /* Use actual working point for scaling */
  for (i=0;i<solverData->n;i++){
    solverData->xScaling[i] = fmax(systemData->nominal[i],fabs(solverData->x0[i]));
  }
  solverData->xScaling[solverData->n] = 1.0;

  debugVectorDouble(LOG_NLS_V,"Nominal values", systemData->nominal, solverData->n);
  debugVectorDouble(LOG_NLS_V,"Scaling values", solverData->xScaling, solverData->m);


  /* Handle asserts of function calls, mainly necessary for fluid stuff */
  assert = 1;
  giveUp = 1;
  while (tries<=2)
  {
    debugVectorDouble(LOG_NLS_V,"x0", solverData->x0, solverData->n);
    /* evaluate with discontinuities */
    if(data->simulationInfo.discreteCall)
    {
      ((DATA*)data)->simulationInfo.solveContinuous = 0;
    }
    /* evaluate with discontinuities */
 #ifndef OMC_EMCC
    MMC_TRY_INTERNAL(simulationJumpBuffer)
 #endif
    solverData->f(solverData, solverData->x0, solverData->f1);
    /* Try to get out of here!!! */
    error_f        = vecNorm2(solverData->n, solverData->f1);
    if ((error_f - solverData->error_f)<=0)
    {
      success = 1;
      /* debug information */
      debugString(LOG_NLS_V, "NO ITERATION NECESSARY!!!");
      debugString(LOG_NLS_V, "******************************************************");
      debugString(LOG_NLS_V,"SYSTEM SOLVED");
      debugInt(LOG_NLS_V,   "number of function calls: ",solverData->numberOfFunctionEvaluations-numberOfFunctionEvaluationsOld);
      debugString(LOG_NLS_V, "------------------------------------------------------");
        /* take the solution */
      vecCopy(solverData->n, solverData->x0, systemData->nlsx);
      debugVectorDouble(LOG_NLS_V,"Solution", solverData->x0, solverData->n);
      /* reset continous flag */
      ((DATA*)data)->simulationInfo.solveContinuous = 0;

      free(relationsPreBackup);

      /* write statistics */
      systemData->numberOfFEval = solverData->numberOfFunctionEvaluations;

      return success;
    }
    solverData->fJac_f(solverData, solverData->x0, solverData->fJac);
    vecCopy(solverData->n, solverData->f1, solverData->fJac + solverData->n*solverData->n);
    vecCopy(solverData->n*solverData->m, solverData->fJac, solverData->fJacx0);
    if (mixedSystem)
      memcpy(relationsPreBackup, data->simulationInfo.relations, sizeof(modelica_boolean)*data->modelData.nRelations);
    /* calculate scaling factor of residuals */
    matVecMultAbsBB(solverData->n, solverData->fJac, solverData->ones, solverData->resScaling);
    debugVectorDouble(LOG_NLS_JAC, "residuum scaling:", solverData->resScaling, solverData->n);
    scaleMatrixRows(solverData->n, solverData->m, solverData->fJac);

    pos = solverData->n;
    assert = (solveSystemWithTotalPivotSearch(solverData->n, solverData->dy0, solverData->fJac, solverData->indRow, solverData->indCol, &pos, &rank) != 0);
    if (!assert)
      debugString(LOG_NLS_V, "regular initial point!!!");
    giveUp = 0;
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
 #endif
    if (assert)
    {
      tries += 1;
    }
    else
      break;
    /* break symmetry, when varying start values */
    /* try to find regular initial point, iff necessary */
    if (tries == 1)
    {
      debugString(LOG_NLS_V, "assert handling:\t vary initial guess by +1%.");
      for(i = 0; i < solverData->n; i++)
        solverData->x0[i] = solverData->xStart[i] + solverData->xScaling[i]*i/solverData->n*0.01;
    }
    if (tries == 2)
    {
      debugString(LOG_NLS_V,"assert handling:\t vary initial guess by +10%.");
      for(i = 0; i < solverData->n; i++)
        solverData->x0[i] = solverData->xStart[i] + solverData->xScaling[i]*i/solverData->n*0.1;
    }
  }
  ((DATA*)data)->simulationInfo.solveContinuous = 1;
  vecCopy(solverData->n, solverData->x0, solverData->x);
  vecCopy(solverData->n, solverData->f1, solverData->fx0);
  /* start solving loop */
  while(!giveUp && !success)
  {
    giveUp = 1;

    solverData->info = 0;
    /*if (!skipNewton) newtonAlgorithm(solverData, solverData->x); */
    if (!skipNewton){

      /* set x vector */
      if(data->simulationInfo.discreteCall)
        memcpy(systemData->nlsx, solverData->x, solverData->n*(sizeof(double)));
      else
        memcpy(systemData->nlsxExtrapolation, solverData->x, solverData->n*(sizeof(double)));

      newtonAlgorithm(solverData, solverData->x);
      if (solverData->info == -1){
        solverDataHybrid = (DATA_HYBRD*)(solverData->dataHybrid);
        systemData->solverData = solverDataHybrid;

        solverData->info = solveHybrd(data, sysNumber);

        memcpy(solverData->x, systemData->nlsx, solverData->n*(sizeof(double)));
        systemData->solverData = solverData;
      }
    }

    /* solution found */
    if(solverData->info == 1)
    {
      success = 1;
      /* This case may be switched off, because of event chattering!!!*/
      if(mixedSystem && data->simulationInfo.discreteCall && (alreadyTested<1))
      {
        debugVectorInt(LOG_NLS_V,"Relations Pre vector ", ((DATA*)data)->simulationInfo.relationsPre, ((DATA*)data)->modelData.nRelations);
        debugVectorInt(LOG_NLS_V,"Relations Backup vector ", relationsPreBackup, ((DATA*)data)->modelData.nRelations);
        ((DATA*)data)->simulationInfo.solveContinuous = 0;
        solverData->f(solverData, solverData->x, solverData->f1);
        debugVectorInt(LOG_NLS_V,"Relations vector ", ((DATA*)data)->simulationInfo.relations, ((DATA*)data)->modelData.nRelations);
        if (isNotEqualVectorInt(((DATA*)data)->modelData.nRelations, ((DATA*)data)->simulationInfo.relations, relationsPreBackup)>0)
        {
          /* re-run the solution process, since relations in the system have changed */
          success = 0;
          giveUp = 0;
          runHomotopy = 0;
          alreadyTested = 1;
          vecCopy(solverData->n, solverData->x0, solverData->x);
          vecCopy(solverData->n, solverData->fx0, solverData->f1);
          vecCopy(solverData->n*solverData->m, solverData->fJacx0, solverData->fJac);

          /* calculate scaling factor of residuals */
          matVecMultAbsBB(solverData->n, solverData->fJac, solverData->ones, solverData->resScaling);
          scaleMatrixRows(solverData->n, solverData->m, solverData->fJac);

          pos = solverData->n;
          solveSystemWithTotalPivotSearch(solverData->n, solverData->dy0, solverData->fJac,   solverData->indRow, solverData->indCol, &pos, &rank);
          debugDouble(LOG_NLS,"solve mixed system at time : ", solverData->timeValue);
          continue;
        }
      }
      if (success)
      {
        debugString(LOG_NLS_V,"SYSTEM SOLVED");
        debugInt(LOG_NLS_V,   "homotopy method:          ",runHomotopy);
        debugInt(LOG_NLS_V,   "number of function calls: ",solverData->numberOfFunctionEvaluations-numberOfFunctionEvaluationsOld);
        printUnknowns(LOG_NLS, solverData);
        debugString(LOG_NLS_V, "------------------------------------------------------");
        /* take the solution */
        vecCopy(solverData->n, solverData->x, systemData->nlsx);
        debugVectorDouble(LOG_NLS_V,"Solution", solverData->x, solverData->n);
        /* reset continous flag */
        ((DATA*)data)->simulationInfo.solveContinuous = 0;
        break;
      }
    }
    if (!success && runHomotopy>=3) break;
    /* Start homotopy search for new start values */
    vecCopy(solverData->n, solverData->x0, solverData->x);
    runHomotopy++;
    /* debug output */
    debugString(LOG_NLS_HOMOTOPY, "======================================================");
    debugInt(LOG_NLS_HOMOTOPY, "RUN HOMOTOPY",runHomotopy);
    if (runHomotopy == 1)
    {
      /* store x0 and calculate f(x0) -> newton homotopy, fJac(x0) -> taylor, affin homotopy */
      solverData->homotopyMethod = 1;
      solverData->h_function = wrapper_fvec_homotopy_newton;
      solverData->hJac_dh = wrapper_fvec_homotopy_newton_der;
      solverData->startDirection = 1.0;
      debugDouble(LOG_NLS_HOMOTOPY,"STARTING NEWTON HOMOTOPY METHOD; startDirection = ", solverData->startDirection);
    }
    if (runHomotopy == 2)
    {
      /* store x0 and calculate f(x0) -> newton homotopy, fJac(x0) -> taylor, affin homotopy */
      solverData->homotopyMethod = 1;
      solverData->h_function = wrapper_fvec_homotopy_newton;
      solverData->hJac_dh = wrapper_fvec_homotopy_newton_der;
      solverData->startDirection = -1.0;
      debugDouble(LOG_NLS_HOMOTOPY,"STARTING NEWTON HOMOTOPY METHOD; startDirection = ", solverData->startDirection);
    }
    if (runHomotopy == 3)
    {
      solverData->homotopyMethod = 2;
      solverData->h_function = wrapper_fvec_homotopy_fixpoint;
      solverData->hJac_dh = wrapper_fvec_homotopy_fixpoint_der;
      solverData->startDirection = 1.0;
      debugDouble(LOG_NLS_HOMOTOPY,"STARTING FIXPOINT HOMOTOPY METHOD = ", solverData->startDirection);
    }
    homotopyAlgorithm(solverData, solverData->x);
    if (solverData->info<1)
    {
      skipNewton = 1;
      giveUp = runHomotopy>=3;
    } else
    {
      assert = 1;
#ifndef OMC_EMCC
      MMC_TRY_INTERNAL(simulationJumpBuffer)
 #endif
      solverData->f(solverData, solverData->x, solverData->f1);
      solverData->fJac_f(solverData, solverData->x, solverData->fJac);
      vecCopy(solverData->n, solverData->f1, solverData->fJac + solverData->n*solverData->n);
      /* calculate scaling factor of residuals */
      matVecMultAbsBB(solverData->n, solverData->fJac, solverData->ones, solverData->resScaling);
      debugVectorDouble(LOG_NLS_JAC, "residuum scaling:", solverData->resScaling, solverData->n);
      scaleMatrixRows(solverData->n, solverData->m, solverData->fJac);

      pos = solverData->n;
      assert = (solveSystemWithTotalPivotSearch(solverData->n, solverData->dy0, solverData->fJac,   solverData->indRow, solverData->indCol, &pos, &rank) != 0);
      if (!assert)
        debugString(LOG_NLS_V, "regular initial point!!!");
#ifndef OMC_EMCC
    MMC_CATCH_INTERNAL(simulationJumpBuffer)
 #endif
      if (assert)
      {
        giveUp = 1;
      } else
      {
        giveUp = 0;
        skipNewton = 0;
      }
    }
  }
  if (!success)
  {
    debugString(LOG_NLS_V,"Homotopy solver did not converge!");
  }
  free(relationsPreBackup);

  /* write statistics */
  systemData->numberOfFEval = solverData->numberOfFunctionEvaluations;
  systemData->numberOfIterations = solverData->numberOfIterations;

  return success;
}
