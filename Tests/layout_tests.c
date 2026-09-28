#include "SWLayout.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks=0;
#define CHECK(c) do { checks++; if(!(c)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#c); abort(); } } while(0)
static SWDisplay basic[]={
    {1,true,{0,0,1512,982},{0,38,1512,944}},
    {2,false,{1512,0,2560,1440},{1512,25,2560,1415}}
};
static SWLayoutPlan plan(SWRect w,SWDisplay *ds,size_t n,double margin) {
    return SWMakePlan(w,ds,n,0,0,margin,3);
}
static void deterministic(void) {
    SWRect target=SWMarginFrame(basic[0],50);
    CHECK(SWRectNear(target,(SWRect){50,38,1462,944},0));
    SWLayoutPlan p=plan((SWRect){150,100,900,700},basic,2,50);
    CHECK(p.action==SWLayoutInternal && !p.crossesDisplay);
    CHECK(SWRectNear(p.target,target,0));
    p=plan(target,basic,2,50);
    CHECK(p.action==SWLayoutExternal && p.targetIndex==1 && p.crossesDisplay);
    CHECK(SWRectNear(p.target,basic[1].visibleFrame,0));
    p=plan(basic[1].visibleFrame,basic,2,50);
    CHECK(p.action==SWLayoutInternal && p.targetIndex==0 && p.crossesDisplay);
    SWRect noisy=target; noisy.x+=2; noisy.width-=2;
    CHECK(plan(noisy,basic,2,50).action==SWLayoutExternal);
    noisy.x+=4;
    CHECK(plan(noisy,basic,2,50).action==SWLayoutInternal);
    SWRect onlyX={50,100,900,500};
    CHECK(plan(onlyX,basic,2,50).action==SWLayoutInternal);
    CHECK(plan(target,basic,2,60).action==SWLayoutInternal);
    CHECK(plan(target,basic,1,50).action==SWLayoutKeep);
    CHECK(plan((SWRect){0,38,1000,500},basic,1,50).action==SWLayoutInternal);
    SWDisplay dock=basic[0]; dock.visibleFrame.x=70; dock.visibleFrame.width-=70;
    CHECK(SWMarginFrame(dock,50).x==70);
    CHECK(SWMarginFrame(dock,100).x==100);
    CHECK(SWMarginFrame(dock,0).x==70);
    CHECK(SWMarginFrame(basic[0],0).x==0);
    SWDisplay externalOnly=basic[1];
    p=plan((SWRect){1600,200,900,500},&externalOnly,1,50);
    CHECK(p.action==SWLayoutClamshell && !p.crossesDisplay);
    CHECK(plan(SWMarginFrame(externalOnly,50),&externalOnly,1,50).action==SWLayoutKeep);
    CHECK(SWFindDisplay((SWRect){1400,100,800,600},basic,2)==1);
    CHECK(SWFindDisplay((SWRect){1200,100,400,600},basic,2)==0);
    CHECK(SWFindDisplay((SWRect){-5000,100,300,500},basic,2)==0);
    SWDisplay negative[]={basic[0],{3,false,{-2560,-1440,2560,1440},{-2560,-1415,2560,1415}}};
    p=plan(negative[1].visibleFrame,negative,2,50);
    CHECK(p.action==SWLayoutInternal && SWRectNear(p.target,target,0));
    p=plan(target,negative,2,50);
    CHECK(p.action==SWLayoutExternal && p.target.x==-2560 && p.target.y==-1415);
    SWDisplay primaryExternal[]={
        {4,false,{0,0,2560,1440},{0,25,2560,1415}},
        {5,true,{-1512,400,1512,982},{-1512,438,1512,944}}
    };
    CHECK(SWMarginFrame(primaryExternal[1],50).x==-1462);
    p=plan(SWMarginFrame(primaryExternal[1],50),primaryExternal,2,50);
    CHECK(p.targetIndex==0 && p.action==SWLayoutExternal);
    SWDisplay three[]={basic[0],basic[1],{9,false,{-2000,0,2000,1200},{-2000,25,2000,1175}}};
    p=SWMakePlan(target,three,3,9,0,50,3);
    CHECK(p.action==SWLayoutExternal && p.targetIndex==2);
    p=SWMakePlan(target,three,3,888,0,50,3);
    CHECK(p.targetIndex==1);
    CHECK(SWMakePlan(target,NULL,0,0,0,50,3).action==SWLayoutInvalid);
    CHECK(plan((SWRect){0,0,0,100},basic,2,50).action==SWLayoutInvalid);
    CHECK(plan(target,basic,2,-1).action==SWLayoutInvalid);
    CHECK(plan(target,basic,2,501).action==SWLayoutInvalid);
    CHECK(plan(target,basic,2,NAN).action==SWLayoutInvalid);
    CHECK(SWMakePlan(target,basic,2,0,0,50,-1).action==SWLayoutInvalid);
    CHECK(SWMakePlan(target,basic,2,0,0,50,NAN).action==SWLayoutInvalid);
    CHECK(!SWRectNear(target,target,-1));
    CHECK(!SWRectValid((SWRect){INFINITY,0,10,10}));
    CHECK(SWFindDisplay(target,NULL,2)==SIZE_MAX);
    CHECK(SWRectIntersectionArea((SWRect){0,0,10,10},(SWRect){10,0,10,10})==0);
    CHECK(SWRectIntersectionArea((SWRect){0,0,10,10},(SWRect){5,5,10,10})==25);
    SWDisplay tiny={1,true,{0,0,400,400},{0,20,400,380}};
    CHECK(plan((SWRect){0,30,200,300},&tiny,1,350).action==SWLayoutInvalid);
    SWDisplay scaled[]={basic[0],basic[1]};
    scaled[0].visibleFrame=(SWRect){0,38.5,1512,943.5};
    p=plan((SWRect){20,50,1000,500},scaled,2,50);
    CHECK(p.target.y==38.5 && p.target.height==943.5);
}
static void dockSelection(void) {
    SWDisplay ds[]={basic[0],basic[1],{9,false,{-2000,0,2000,1200},{-2000,25,2000,1175}}};
    SWRect internal=ds[0].visibleFrame;
    SWLayoutPlan p=SWMakePlan(internal,ds,3,2,2,50,3);
    CHECK(p.action==SWLayoutExternal && p.targetIndex==1);
    CHECK(p.target.x==1562 && p.target.width==2510);
    p=SWMakePlan(p.target,ds,3,2,2,50,3);
    CHECK(p.action==SWLayoutInternal && SWRectNear(p.target,internal,0));
    p=SWMakePlan(internal,ds,3,9,2,50,3);
    CHECK(p.targetIndex==2 && SWRectNear(p.target,ds[2].visibleFrame,0));
    p=SWMakePlan(internal,ds,3,9,9,80,3);
    CHECK(p.target.x==-1920 && p.target.width==1920);
    ds[2].visibleFrame.x+=100; ds[2].visibleFrame.width-=100;
    p=SWMakePlan(internal,ds,3,9,9,50,3);
    CHECK(p.target.x==-1900); /* System reservation is not added twice. */
    p=SWMakePlan(internal,ds,3,9,9,120,3);
    CHECK(p.target.x==-1880);
    p=SWMakePlan(internal,ds,3,9,9,0,3);
    CHECK(SWRectNear(p.target,ds[2].visibleFrame,0));
    p=SWMakePlan(internal,ds,3,9,UINT32_MAX,50,3);
    CHECK(SWRectNear(p.target,ds[2].visibleFrame,0));
    /* Selection and cross-screen target do not depend on array order. */
    SWDisplay reordered[]={ds[2],ds[0],ds[1]};
    p=SWMakePlan(internal,reordered,3,2,2,50,3);
    CHECK(p.targetIndex==2 && p.target.x==1562);
    /* One display overrides both a disconnected selection and built-in default. */
    p=SWMakePlan(basic[1].visibleFrame,&basic[1],1,0,UINT32_MAX,50,3);
    CHECK(p.action==SWLayoutClamshell && p.target.x==1562);
    CHECK(SWMakePlan(p.target,&basic[1],1,0,UINT32_MAX,50,3).action==SWLayoutKeep);
    p=SWMakePlan(internal,&basic[0],1,0,2,50,3);
    CHECK(p.target.x==50 && !p.crossesDisplay);
    /* With multiple external-only screens, only the selected one has a margin. */
    SWDisplay external[]={basic[1],ds[2]};
    p=SWMakePlan(external[0].visibleFrame,external,2,0,9,50,3);
    CHECK(p.action==SWLayoutKeep);
    p=SWMakePlan((SWRect){-1800,100,900,500},external,2,0,9,120,3);
    CHECK(p.action==SWLayoutClamshell && p.target.x==-1880 && !p.crossesDisplay);
    SWDisplay narrow[]={basic[0],{2,false,{1512,0,400,600},{1512,25,400,575}}};
    CHECK(SWMakePlan(internal,narrow,2,2,2,350,3).action==SWLayoutInvalid);
}
static unsigned randomState=20260927;
static unsigned nextRandom(void) { randomState=randomState*1664525u+1013904223u; return randomState; }
static void randomized(void) {
    for(unsigned i=0;i<20000;i++) {
        SWDisplay ds[2]={basic[0],basic[1]};
        ds[0].visibleFrame.x=nextRandom()%121;
        ds[0].visibleFrame.width=ds[0].frame.width-ds[0].visibleFrame.x;
        double margin=nextRandom()%501;
        SWRect w={(double)((int)(nextRandom()%8000)-3000),
                  (double)((int)(nextRandom()%3000)-1000),
                  (double)(300+nextRandom()%2200),(double)(300+nextRandom()%1200)};
        SWLayoutPlan p=plan(w,ds,2,margin);
        CHECK(p.action!=SWLayoutInvalid);
        CHECK(p.currentIndex<2 && p.targetIndex<2);
        SWRect v=ds[p.targetIndex].visibleFrame;
        CHECK(SWRectValid(p.target));
        CHECK(p.target.x>=v.x && p.target.y>=v.y);
        CHECK(p.target.x+p.target.width<=v.x+v.width+0.00001);
        CHECK(p.target.y+p.target.height<=v.y+v.height+0.00001);
        if(ds[p.targetIndex].builtIn) {
            CHECK(p.target.x>=ds[p.targetIndex].frame.x+margin);
            CHECK(plan(p.target,ds,2,margin).action==SWLayoutExternal);
        } else {
            CHECK(SWRectNear(p.target,v,0));
            CHECK(plan(p.target,ds,2,margin).action==SWLayoutInternal);
        }
    }
}
int main(void) {
    deterministic(); dockSelection(); randomized();
    printf("PASS: %u checks (deterministic + 20,000 randomized layout cases)\n",checks);
    return 0;
}
