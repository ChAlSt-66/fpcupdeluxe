unit m_any_to_freertosarm;
{ Cross compiles from any platform with correct binutils to Embedded ARM
Copyright (C) 2020 Alf

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Library General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at your
option) any later version with the following modification:

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent modules,and
to copy and distribute the resulting executable under terms of your choice,
provided that you also meet, for each linked independent module, the terms
and conditions of the license of that module. An independent module is a
module which is not derived from or based on this library. If you modify
this library, you may extend this exception to your version of the library,
but you are not obligated to do so. If you do not wish to do so, delete this
exception statement from your version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
for more details.

You should have received a copy of the GNU Library General Public License
along with this library; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

implementation

uses
  m_crossinstaller, fpcuputil;

type
  TAny_FreeRTOSArm = class(TCrossInstaller)
  private
    FAlreadyWarned: boolean; //did we warn user about errors and fixes already?
  public
    function GetLibs(Basepath:string):boolean;override;
    function GetBinUtils(Basepath:string):boolean;override;
    constructor Create;
    destructor Destroy; override;
  end;

{ TAny_FreeRTOSArm }

function TAny_FreeRTOSArm.GetLibs(Basepath:string): boolean;
const
  StaticLibName1='libfreertos.a';
  StaticLibName2='libc_nano.a';
  ABINAMES:array[0..2] of string = ('eabihf','eabi','default');
var
  aSubarchName:string;
  aIndex:integer;
  aABI:string;
begin
  result:=FLibsFound;

  if result then exit;

  if (FSubArch<>TSUBARCH.saNone) then
  begin
    aSubarchName:=GetEnumNameSimple(TypeInfo(TSUBARCH),Ord(FSubArch));
    ShowInfo('Cross-libs: We have a subarch: '+aSubarchName);
  end
  else ShowInfo('Cross-libs: No subarch defined. Expect fatal errors.',etError);

  // simple: check presence of library file in basedir
  result:=SearchLibrary(Basepath,LIBCNAME);
  // search local paths based on libbraries provided for or adviced by fpc itself
  if not result then
    result:=SimpleSearchLibrary(BasePath,DirName,LIBCNAME);
  if ((not result) AND (FSubArch<>TSUBARCH.saNone)) then
    result:=SimpleSearchLibrary(BasePath,IncludeTrailingPathDelimiter(DirName)+aSubarchName,LIBCNAME);

  // do the same as above, but look for a static freertos lib
  if not result then
    result:=SearchLibrary(Basepath,StaticLibName1);
  // search local paths based on libbraries provided for or adviced by fpc itself
  if not result then
    result:=SimpleSearchLibrary(BasePath,DirName,StaticLibName1);
  if ((not result) AND (FSubArch<>TSUBARCH.saNone)) then
    result:=SimpleSearchLibrary(BasePath,IncludeTrailingPathDelimiter(DirName)+aSubarchName,StaticLibName1);

  // do the same as above, but look for a static libc_nano lib
  if not result then
    result:=SearchLibrary(Basepath,StaticLibName2);

  // search local paths based on libbraries provided for or adviced by fpc itself
  if not result then
    result:=SimpleSearchLibrary(BasePath,DirName,StaticLibName2);
  if ((not result) AND (FSubArch<>TSUBARCH.saNone)) then
    result:=SimpleSearchLibrary(BasePath,IncludeTrailingPathDelimiter(DirName)+aSubarchName,StaticLibName2);

  // search local paths based on libbraries provided for or adviced by https://github.com/michael-ring/freertos4fpc
  if ((not result) AND (FSubArch<>TSUBARCH.saNone)) then
  begin
    result:=SimpleSearchLibrary(BasePath,ConcatPaths([DirName,'lib',aSubarchName]),StaticLibName2);
    if (not result) then
    begin
      for aABI in ABINAMES do
      begin
        result:=SimpleSearchLibrary(BasePath,ConcatPaths([DirName,'lib',aSubarchName,aABI]),StaticLibName2);
        if result then break;
      end;
    end;
  end;

  if result then
  begin
    SearchLibraryInfo(true);
    FLibsFound:=True;

    // Perform subarch magic for libpath
    if (FSubArch<>TSUBARCH.saNone) then
    begin
      if (Pos(aSubarchName,FLibsPath)>0) then
        // we have a libdir with a subarch inside: make it universal !!
        FLibsPath:=StringReplace(FLibsPath,aSubarchName,'$FPCSUBARCH',[]);
    end;

    // Perform ABI magic for libpath
    aIndex:=Pos(Self.RegisterName,FLibsPath);
    if (aIndex<>-1) then
    begin
      for aABI in ABINAMES do
      begin
        if (Pos(DirectorySeparator+aABI+DirectorySeparator,FLibsPath,aIndex)>0) then
        begin
          // we have a libdir with a ABI inside: make it universal !!
          FLibsPath:=StringReplace(FLibsPath,DirectorySeparator+aABI+DirectorySeparator,DirectorySeparator+'$FPCABI'+DirectorySeparator,[]);
          break;
        end;
      end;
    end;

    AddFPCCFGSnippet('-Fl'+IncludeTrailingPathDelimiter(FLibsPath));
  end;
end;

function TAny_FreeRTOSArm.GetBinUtils(Basepath:string): boolean;
var
  AsFile,aOption: string;
  i:integer;
begin
  result:=inherited;
  if result then exit;

  FBinUtilsPrefix:=GetCPU(TargetCPU)+'-none-eabi-';

  // Start with any names user may have given
  AsFile:=FBinUtilsPrefix+'as'+GetExeExt;

  result:=SearchBinUtil(BasePath,AsFile);
  if not result then
    result:=SimpleSearchBinUtil(BasePath,DirName,AsFile);

  SearchBinUtilsInfo(result);

  if result then
  begin
    FBinsFound:=true;
    // Configuration snippet for FPC
    AddFPCCFGSnippet('-FD'+IncludeTrailingPathDelimiter(FBinUtilsPath));
    AddFPCCFGSnippet('-XP'+FBinUtilsPrefix); {Prepend the binutils names};
  end;
end;

constructor TAny_FreeRTOSArm.Create;
begin
  inherited Create;
  FTargetCPU:=TCPU.arm;
  FTargetOS:=TOS.freertos;
  Reset;
  FAlreadyWarned:=false;
  ShowInfo;
end;

destructor TAny_FreeRTOSArm.Destroy;
begin
  inherited Destroy;
end;

var
  Any_FreeRTOSArm:TAny_FreeRTOSArm;

initialization
  Any_FreeRTOSArm:=TAny_FreeRTOSArm.Create;
  RegisterCrossCompiler(Any_FreeRTOSArm.RegisterName,Any_FreeRTOSArm);

finalization
  Any_FreeRTOSArm.Destroy;

end.

