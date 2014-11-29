typedef unsigned char uchar;

#include <platform.h>
#include <stdio.h>
#include "pgmIO.h"
#define IMHT 16
#define IMWD 16

char infname[] = "test9.pgm";     //put your input image path here, absolute path
char outfname[] = "test10.pgm"; //put your output image path here, absolute path

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

void fillArray(chanend c, uchar array[], int arraySize){
  for (int i=0; i<arraySize; i++){
      c :> array[i];
  }
  return;
}

//should be able to be replaced with better pointing for speedup
void makeEqualArrays(uchar one[], uchar two[], int size){
  for(int i=0; i<size; i++){
      one[i] = two[i];
  }
  return;
}

void establishArrays(int numberOfCycles, chanend c_in, uchar above[], uchar calculate[], uchar below[]) {
  //first time leaves row above to 0s
  //and reads two lines not one
  if (numberOfCycles != 1) {
      makeEqualArrays(above,calculate,IMWD);
      makeEqualArrays(calculate,below,IMWD);
  }
  else {
      fillArray(c_in, calculate, IMWD);
  }

  //last time sets row below to 0s
  if (numberOfCycles != IMHT) {
      fillArray(c_in, below, IMWD);
  }
  else {
      uchar below[IMWD] = {0};
  }
  return;
}

void read(uchar above[], uchar calculate[], uchar below[], chanend fromDist, int cellIndex) {
  fromDist :> above[cellIndex];
  fromDist :> calculate[cellIndex];
  fromDist :> below[cellIndex];
}

uchar addOneIfLive(uchar count, uchar input){
  if (input == 255){
      return count+1;
  }
  return count;
}

uchar numberOfNeighbours(uchar abv[],
                         uchar cal[],
                         uchar blw[],
                         int cellIndex) {
  uchar output = 0;
  output = addOneIfLive(output,abv[cellIndex]);
  output = addOneIfLive(output,blw[cellIndex]);
  if (cellIndex != 0) {
      output = addOneIfLive(output,abv[cellIndex-1]);
      output = addOneIfLive(output,blw[cellIndex-1]);
      output = addOneIfLive(output,cal[cellIndex-1]);
  }
  if (cellIndex != IMWD-1) {
      output = addOneIfLive(output,cal[cellIndex+1]);
      output = addOneIfLive(output,abv[cellIndex+1]);
      output = addOneIfLive(output,blw[cellIndex+1]);
  }

  return output;
}

void calculateCell(uchar abv[],
                    uchar cal[],
                    uchar blw[],
                    int cellIndex,
                    streaming chanend toHarvest){
  uchar neighbours;

  neighbours = numberOfNeighbours(abv,cal,blw,cellIndex);

  //game logic
  if (cal[cellIndex] == 0){
      //printArray(cal,IMWD);
      if (neighbours == 3){
          toHarvest <: (uchar) 255;
      }
      else {
          toHarvest <: (uchar) 0;
      }
  }
  else {
      if (neighbours < 2){
          toHarvest <: (uchar) 0;
      }
      else if (neighbours <= 3) {
          toHarvest <: (uchar) 255;
      }
      else {
          toHarvest <: (uchar) 0;
      }
  }

  return;
}

//code sent to worker from dist is:
//0 - no work remains
//(1-(IMHT))(1-IMWD)(0|255)+ - line number, how much to process, info
//3 -
//code sent from worker to dist is:
//1 - finished work ready for more
//code sent to worker from dist is:
//1 - about to send work
void worker(chanend fromDist, streaming chanend toHarvest) {
  int lineNumber;
  int width;
  int cellIndex = 0;
  uchar above[IMWD];
  uchar below[IMWD];
  uchar calculate[IMWD];

  while(1){
      fromDist <: (uchar) 1;
      fromDist :> lineNumber;
      if (lineNumber == 0) break;
      fromDist :> width;
      for (int i=0; i<width; i++){
          read(above,calculate,below,fromDist,i);
      }
      cellIndex = 0;
      toHarvest <: lineNumber;
      for (int i=0; i<width; i++){
          calculateCell(above,calculate,below,i,toHarvest);
      }

  }

  printf("Worker terminating\n");

  return;
}

void sendWork(chanend toWork, uchar above[], uchar calculate[], uchar below[], int lineNumber, int arraySize) {
  //send line number
  toWork <: lineNumber;
  //send size of blocks
  toWork <: arraySize;
  //send the three arrays
  for (int i=0; i<arraySize; i++){
      toWork <: above[i];
      toWork <: calculate[i];
      toWork <: below[i];
  }
  return;
}

void distributor(chanend c_in, chanend toWork[], chanend toStore[])
{
  uchar above[IMWD] = {0};
  uchar below[IMWD];
  uchar calculate[IMWD];

  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  int lineNumber = 1;
  uchar singleWorkerStatus;

  //ARRAYS ESTABLISHED, WORKERS CAN NOW BE SENT
  //THE CALCULATION ARRAY TO COMPUTE
  //single worker status code:
  //1 - Wants work
  while(1){
    printf("%d\n",lineNumber);
    //ESTABLISH THE ARRAYS
    establishArrays(lineNumber,c_in,above,calculate,below);
    //printf("%d\n",lineNumber);
    select {
      case toWork[0] :> singleWorkerStatus:
        //printf("worker[%d]\n",0);
        if (singleWorkerStatus == 1){
            sendWork(toWork[0],above,calculate,below,lineNumber,IMWD);
        }
        break;
      case toWork[1] :> singleWorkerStatus:
      //printf("worker[%d]\n",1);
        if (singleWorkerStatus == 1){
            sendWork(toWork[1],above,calculate,below,lineNumber,IMWD);
        }
        break;
      case toWork[2] :> singleWorkerStatus:
      //printf("worker[%d]\n",2);
        if (singleWorkerStatus == 1){
            sendWork(toWork[2],above,calculate,below,lineNumber,IMWD);
        }
        break;
      case toWork[3] :> singleWorkerStatus:
      //printf("worker[%d]\n",3);
        if (singleWorkerStatus == 1){
            sendWork(toWork[3],above,calculate,below,lineNumber,IMWD);
        }
        break;

    }

    if (lineNumber == IMHT) break;
    lineNumber++;
  }

  for (int i=0; i<4; i++){
      toWork[i] :> singleWorkerStatus;
      toWork[i] <: 0;
  }

  printf( "ProcessImage:Done...\n" );
}

void sendRowToStore(int rowCalculated, streaming chanend workToHarvester[], chanend harvesterToStore[],int index) {
  uchar cellStore;
  harvesterToStore[rowCalculated%4] <: 2;
  harvesterToStore[rowCalculated%4] <: rowCalculated;
  for (int lineIndex = 0; lineIndex < IMWD; lineIndex++){
      workToHarvester[index] :> cellStore;
      harvesterToStore[rowCalculated%4] <: cellStore;
  }
}

void harvester(streaming chanend workToHarvester[], chanend harvesterToStore[], chanend toOut){
  int rowCalculated;
  int rowsRead = 0;
  while (1) {

    select {
      case workToHarvester[0] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,0);
        break;
      case workToHarvester[1] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,1);
        break;
      case workToHarvester[2] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,2);
        break;
      case workToHarvester[3] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,3);
        break;
    }
    rowsRead++;
    //atm this just prints and terminates after one cycle
    //this needs to be changed to be done at the distrib's instruction
    //by adding a read from distrib at the start (like in worker)
    if (rowsRead == IMWD) {
        uchar cell;
        for (int i=1;i<=IMHT;i++){
            harvesterToStore[i%4] <: 1;
            harvesterToStore[i%4] <: i;
            for (int j=0;j<IMWD;j++){
              harvesterToStore[i%4] :> cell;
              toOut <: cell;

            }

        }
        for (int i=0;i<4;i++){
            harvesterToStore[i] <: 0;
        }
        break;
    }
  }
  return;
}

//from distib needs to be added so we can easily cycle into another round
void store(chanend fromHarvester,chanend fromDistributor) {
  //change to make sure it always has space
  uchar store[IMHT/4][IMWD+1];
  int harvestInstruction;
  int distribInstruction;
  int rowNumber;
  int storeLocation = 0;
  while(1){
      //so harvester instructions only proc if a message is sent from harvester
      harvestInstruction = -1;
      select {
        case fromHarvester :> harvestInstruction:
          break;
        case fromDistributor :> distribInstruction:
          break;
      }
      //instruction from harvester
      //0 means terminate
      //1 means harvester wants info to print out
      //2 means harvester will send info into the store
      if (harvestInstruction == 2){
        for (int i=0; i<IMHT/4; i++){
          fromHarvester :> rowNumber;
          store[storeLocation][0] = (uchar) rowNumber;
          //just dont even ask why this cant be it's own variable
          for(i=1;i<=IMWD;i++){

              fromHarvester :> store[storeLocation][i];
          }
          storeLocation++;
        }
      }
      else if (harvestInstruction == 1) {
          //harvester tells the worker which row it wants
          fromHarvester :> rowNumber;
          uchar found = 0;
          for (int i=0; i<IMHT/4; i++){
              if (store[i][0] == rowNumber){
                  for (int j=1;j<=IMWD;j++){
                      fromHarvester <: store[i][j];
                  }
                  found = 1;
                  break;
              }
          }
          if (!found) {
              printf("WORKER ERROR FINDING ARRAY\n");
              for (int i=0; i<IMHT/4; i++){
                  printf("%d,%d\n",i,store[i][0]);
              }
          }
          else found = 0;
      }
      else if (harvestInstruction == 0) break;
      //


  }
  printf("terminating store\n");
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
      //printf( "-%4.1d ", line[ x ] );
    }
    //printf("\n");
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
  streaming chan workToHarvester[4];
  chan harvesterToOut;
  chan harvesterToStore[4];
  chan distribToStore[4];
  par //extend/change this par statement
  {
    on stdcore[1]: DataInStream( infname, c_inIO );
    on stdcore[0]: distributor( c_inIO, distToWork,distribToStore);
    on stdcore[2]: DataOutStream( outfname, harvesterToOut );
    on stdcore[3]: harvester(workToHarvester,harvesterToStore,harvesterToOut);
    on stdcore[0]: worker(distToWork[0],workToHarvester[0]);
    on stdcore[1]: worker(distToWork[1],workToHarvester[1]);
    on stdcore[2]: worker(distToWork[2],workToHarvester[2]);
    on stdcore[3]: worker(distToWork[3],workToHarvester[3]);
    on stdcore[0]: store(harvesterToStore[0],distribToStore[0]);
    on stdcore[1]: store(harvesterToStore[1],distribToStore[1]);
    on stdcore[2]: store(harvesterToStore[2],distribToStore[2]);
    on stdcore[3]: store(harvesterToStore[3],distribToStore[3]);
  }
  //printf( "Main:Done...\n" );
  return 0;
}


