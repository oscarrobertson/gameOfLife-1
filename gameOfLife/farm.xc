/////////////////////////////////////////////////////////////////////////////////////////
//
// COMS20001 - Assignment 2 
//
/////////////////////////////////////////////////////////////////////////////////////////

typedef unsigned char uchar;

#include <platform.h>
#include <stdio.h>
#include "pgmIO.h"
#include <timer.h>
#define IMHT 16
#define IMWD 16

char infname[] = "test.pgm";     //put your input image path here, absolute path
char outfname[] = "testout.pgm"; //put your output image path here, absolute path

uchar above[IMWD] = {0};
uchar calculate[IMWD];
uchar below[IMWD];

void printArray(uchar array[], int arraysize){
  printf("[");
  for(int i=0;i<arraysize;i++){
      printf("%d,",array[i]);
  }
  printf("]\n");
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from pgm file with path and name infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream:Start...\n" );
  res = _openinpgm( infname, IMWD, IMHT );
  if( res )
  {
    printf( "DataInStream:Error openening %s\n.", infname );
    return;
  }
  for( int y = 0; y < IMHT; y++ )
  {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ )
    {
      c_out <: line[ x ];
      //printf( "-%4.1d ", line[ x ] ); //uncomment to show image values
    }
    //printf( "\n" ); //uncomment to show image values
  }
  _closeinpgm();
  printf( "DataInStream:Done...\n" );
  return;
}

//should be able to be replaced with better pointing for speedup
void fillArray(chanend c, uchar array[], int arraySize){
  for (int i=0; i<arraySize; i++){
      c :> array[i];
  }
  return;
}

uchar addOneIfLive(uchar count, uchar input){
  if (input == 255){
      return count+1;
  }
  return count;
}

//counts number of neighbours, taking into account ends of arrays
uchar numberOfNeighbours(uchar above[], uchar calculate[], uchar below[], int arraySize, int indexToCalc){
  uchar count = 0;
  if (indexToCalc != 0) {
      count = addOneIfLive(count,above[indexToCalc-1]);
      count = addOneIfLive(count,calculate[indexToCalc-1]);
      count = addOneIfLive(count,below[indexToCalc-1]);
  }
  if (indexToCalc != arraySize-1){
      count = addOneIfLive(count,above[indexToCalc+1]);
      count = addOneIfLive(count,calculate[indexToCalc+1]);
      count = addOneIfLive(count,below[indexToCalc+1]);
  }
  count = addOneIfLive(count, above[indexToCalc]);
  count = addOneIfLive(count, below[indexToCalc]);

  return count;
}

//works out what the calcualte row should look like next turn
//CURRENTLY WORKS ON A WHOLE GIVEN ROW, SHOULD BE CHANGED TO ONLY WORK ON PART OF IT
void calculateRow(uchar above[], uchar calculate[], uchar below[], int arraySize, chanend toStore){
  uchar neighbours;

  for (int i=0; i<arraySize; i++){
    neighbours = numberOfNeighbours(above,calculate,below,arraySize,i);

    //game logic
    if (calculate[i] == 0){
        if (neighbours == 3){
            toStore <: (uchar) 255;
        }
        else {
            toStore <: (uchar) 0;
        }
    }
    else {
        if (neighbours < 2){
            toStore <: (uchar) 0;
        }
        else if (neighbours <= 3) {
            toStore <: (uchar) 255;
        }
        else {
            toStore <: (uchar) 0;
        }
    }
  }
  return;
}

void makeEqualArrays(uchar one[], uchar two[], int size){
  for(int i=0; i<size; i++){
      one[i] = two[i];
  }
  return;
}

//code sent to worker from dist is:
//1 - no work remains
//2 (0-(IMWD-1)) (0|255)+ 3 - work ready to be sent, then sends info with start index, then signals completion
//3 -
//code sent from worker to dist is:
//1 - finished work ready for more
void worker(chanend fromDist, streaming chanend toHarvest) {
  uchar store;
  while(1){
      fromDist <: (uchar) 1;
      fromDist :> store;
      if (store == 1) break;

      fromDist :> store;
      fromDist :> store;
  }

  printf("Worker terminating\n");

  return;
}

void establishArrays(uchar numberOfCycles, chanend c_in) {
  //first time leaves row above to 0s
  //and reads two lines not one
  if (numberOfCycles != 0) {
      makeEqualArrays(above,calculate,IMWD);
      makeEqualArrays(calculate,below,IMWD);
  }
  else {
      fillArray(c_in, calculate, IMWD);
  }

  //last time sets row below to 0s
  if (numberOfCycles != IMHT-1) {
      fillArray(c_in, below, IMWD);
  }
  else {
      uchar below[IMWD] = {0};
  }
  return;
}

uchar sendWork(chanend toWork, uchar currentIndex, uchar segmentSize) {
  uchar currentCalculationIndex = currentIndex;
  toWork <: (uchar) 2;
  toWork <: currentCalculationIndex;
  currentCalculationIndex += segmentSize;
  toWork <: currentCalculationIndex;
  return currentCalculationIndex;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to farm out parts of the image...
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend toWork[])
{
  uchar currentCalculationIndex = 0; //where the next worker will begin working on the calculation array
  uchar segmentSize = (uchar) IMWD/2;
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  uchar numberOfCycles = 0;

  uchar singleWorkerStatus = 0;

  while (1){


    //ESTABLISH THE SHARED MEMORY ARRAYS
    establishArrays(numberOfCycles,c_in);

    //ARRAYS ESTABLISHED, WORKERS CAN NOW BE SENT SECTIONS
    //OF THE CALCULATION ARRAY TO COMPUTE
    //send each section to a worker and loop here until the entire row has been computed
    while(1){
      select {
        case toWork[0] :> singleWorkerStatus:
          printf("worker[%d]\n",0);
          if (singleWorkerStatus == 1){
              currentCalculationIndex = sendWork(toWork[0],currentCalculationIndex,segmentSize);
          }
          break;
        case toWork[1] :> singleWorkerStatus:
        printf("worker[%d]\n",1);
          if (singleWorkerStatus == 1){
              currentCalculationIndex = sendWork(toWork[1],currentCalculationIndex,segmentSize);
          }
          break;
        case toWork[2] :> singleWorkerStatus:
        printf("worker[%d]\n",2);
          if (singleWorkerStatus == 1){
              currentCalculationIndex = sendWork(toWork[2],currentCalculationIndex,segmentSize);
          }
          break;
        case toWork[3] :> singleWorkerStatus:
        printf("worker[%d]\n",3);
          if (singleWorkerStatus == 1){
              currentCalculationIndex = sendWork(toWork[3],currentCalculationIndex,segmentSize);
          }
          break;

      }

      if (currentCalculationIndex == IMWD) {
          currentCalculationIndex = 0;
          break;
      }
    }

    //calculateRow(above,calculate,below,IMWD,toStore);

    if(numberOfCycles == IMHT-1) break;

    numberOfCycles++;
  }

  for (int i=0; i<4; i++){
      toWork[i] :> singleWorkerStatus;
      toWork[i] <: (uchar) 1;
  }

  printf( "ProcessImage:Done...\n" );
}

void harvester(streaming chanend workToHarvester[], chanend harvesterToStore[]){
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to pgm image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataOutStream:Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res )
  {
    printf( "DataOutStream:Error opening %s\n.", outfname );
    return;
  }
  for( int y = 0; y < IMHT; y++ )
  {
    for( int x = 0; x < IMWD; x++ )
    {
      c_in :> line[ x ];
      printf( "-%4.1d ", line[ x ] );
    }
    printf("\n");
    _writeoutline( line, IMWD );
  }
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
  return;
}

//MAIN PROCESS defining channels, orchestrating and starting the threads
int main()
{

  chan c_inIO; //extend your channel definitions here
  chan distToWork[4];
  chan workerToStore;
  streaming chan workToHarvester[4];
  chan harvesterToStore[4];
  par //extend/change this par statement
  {
    on stdcore[0]: DataInStream( infname, c_inIO );
    on stdcore[1]: distributor( c_inIO, distToWork);
    on stdcore[2]: DataOutStream( outfname, workerToStore );
    on stdcore[3]: harvester(workToHarvester,harvesterToStore);
    on stdcore[0]: worker(distToWork[0],workToHarvester[0]);
    on stdcore[1]: worker(distToWork[1],workToHarvester[1]);
    on stdcore[2]: worker(distToWork[2],workToHarvester[2]);
    on stdcore[3]: worker(distToWork[3],workToHarvester[3]);

  }
  //printf( "Main:Done...\n" );
  return 0;
}
