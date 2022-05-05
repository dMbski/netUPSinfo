unit upsinfo_nut;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, blcksock, synautil, upsinfo_def;

type
  {this is used only in Execute loop}
  TUPSinfoNUTstatusType = (
    Exec0_Pre,            {precheck}
    Exec1_Bind,           {to bind }
    Exec2_Conn,           {to connect }
    Exec3_LogUsrS,        {login user }
    Exec4_LogUsrR,        {login user response}
    Exec5_LogPasS,        {login pass }
    Exec6_LogPasR,        {login pass response }
    Exec7_ReqInitS,       {request list ups}
    Exec8_ReqInitR,       {request list ups response }
    Exec9_ReqListS,       {request list var }
    Exec10_ReqListR,      {request list var response }
    Exec11_IdleConn,      {idle after list var received }
    Exec12_Err            {there is error and wait for communications }
    );


  { TUPSinfoNUTthread }

  TUPSinfoNUTthread = class(TThread)
  private
    Fsock: TTCPBlockSocket;
    FLocalIP: string;
    FLocalPort: string;
    FRemoteIP: string;
    FRemotePort: string;
    FRemoteUser: string;
    FRemotePass: string;

    FErrorCode: integer;
    FErrorDesc: string;
    FBattery: TUPSbatteryType;
    FInput: TUPSinputType;
    FOutput: TUPSoutputType;
    FDevice: TUPSdeviceType;
    FDeviceId: string;
    FStatus: string;

    procedure resetError;
    procedure clearDevice;
    procedure clearInput;
    procedure clearOutput;
    procedure clearBattery;
    procedure doStatus(stat: string);
    procedure runStatus;
    procedure doData;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    procedure SetLocal(ip, port: string);
    procedure SetRemote(ip, port: string);
    procedure SetCredentials(user, pass: string);
    procedure SetDeviceId(id: string);
  end;

{returns value of paramname from received NUT data}
function GetNUTValue(var rawdata: string; paramname: string): string;
{returns NUTvalue as integer}
function GetNUTint(var rawdata: string; paramname: string): integer;
{returns NUTvalue as float}
function GetNUTdbl(var rawdata: string; paramname: string): extended;

procedure GetNUTtoDevice(var pData: string; var pDev: TUPSdeviceType);
procedure GetNUTtoInput(var pData: string; var pInput: TUPSinputType);
procedure GetNUTtoOutput(var pData: string; var pOutput: TUPSoutputType);
procedure GetNUTtoBatt(var pData: string; var pBatt: TUPSbatteryType);


implementation

uses mainfrm;

function GetNUTValue(var rawdata: string; paramname: string): string;
var
  p: integer;
  s: string;
begin
  Result := '';
  if (Length(rawdata) <= Length(paramname)) or (paramname = '') then
    Exit;

  p := Pos(UpperCase(paramname), UpperCase(rawdata));
  if p = 0 then
    Exit;

  s := rawdata.Substring(-1 + p + Length(paramname));
  //ShowMessage('getnutvalue |'+s + '|');
  Result := Trim(GetBetween('"', '"', s));

end;

function GetNUTint(var rawdata: string; paramname: string): integer;
begin
  Result := StrToIntDef(GetNUTValue(rawdata, paramname), UPSinfo_UnkVal);
end;

function GetNUTdbl(var rawdata: string; paramname: string): extended;
var
  ods: char;
begin
  ods := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := '.';
  Result := StrToFloatDef(GetNUTValue(rawdata, paramname), UPSinfo_UnkVal);
  FormatSettings.DecimalSeparator := ods;
end;

procedure GetNUTtoDevice(var pData: string; var pDev: TUPSdeviceType);
var
  i: integer;
begin

  pDev.Firmware := GetNUTValue(pData, 'ups.firmware');
  pDev.MFR := GetNUTValue(pData, 'device.mfr');
  pDev.Model := GetNUTValue(pData, 'device.model');
  pDev.Serial := GetNUTValue(pData, 'device.serial');
  pDev.StatusRaw := GetNUTValue(pData, 'ups.status');
  pDev.Temperature := GetNUTdbl(pData, 'ups.temperature');

  pDev.Timer := GetNUTint(pData, 'ups.timer.reboot');
  i := GetNUTint(pData, 'ups.timer.shutdown');
  if (pDev.Timer < i) then
    pDev.Timer := i;

  if (pDev.Timer > 0) then
  begin//timer is ticking
    pDev.Status := UPS_StatusShutdown;
  end
  else
  begin
    //read status from ups.status
    if Pos('OL', pDev.StatusRaw) > 0 then
    begin
      pDev.Status := UPS_StatusOL;
    end
    else if Pos('OB', pDev.StatusRaw) > 0 then
    begin
      pDev.Status := UPS_StatusOB;
    end
    else
    begin
      pDev.Status := UPS_StatusUnknown;
    end;

  end;

end;

procedure GetNUTtoInput(var pData: string; var pInput: TUPSinputType);
begin
  pInput.Voltage := GetNUTdbl(pData, 'input.voltage');
  pInput.VoltageNominal := GetNUTdbl(pData, 'input.voltage.nominal');
  pInput.Current := GetNUTdbl(pData, 'input.current');
  pInput.CurrentNominal := GetNUTdbl(pData, 'input.current.nominal');
  pInput.Frequency := GetNUTdbl(pData, 'input.frequency');
  pInput.Load := GetNUTdbl(pData, 'input.load');

  if (pInput.Load = UPSinfo_UnkVal) and (pInput.CurrentNominal > 0) then
    //calculate load %
  begin
    pInput.Load := (pInput.Current / pInput.CurrentNominal) * 100;
  end;

end;

procedure GetNUTtoOutput(var pData: string; var pOutput: TUPSoutputType);
begin
  pOutput.Frequency := GetNUTdbl(pData, 'output.frequency');
  pOutput.CurrentNominal := GetNUTdbl(pData, 'output.current.nominal');
  pOutput.Current := GetNUTdbl(pData, 'output.current');
  pOutput.Voltage := GetNUTdbl(pData, 'output.voltage');
  pOutput.VoltageNominal := GetNUTdbl(pData, 'output.voltage.nominal');
  pOutput.Load := GetNUTdbl(pData, 'ups.load');

  pOutput.Power := GetNUTdbl(pData, 'ups.realpower');
  pOutput.PowerNominal := GetNUTdbl(pData, 'ups.realpower.nominal');
  if (pOutput.Power = UPSinfo_UnkVal) then  //from VA
  begin
    pOutput.Power := GetNUTdbl(pData, 'ups.power');
    pOutput.PowerNominal := GetNUTdbl(pData, 'ups.power.nominal');
  end;
  if (pOutput.Load = UPSinfo_UnkVal) and (pOutput.PowerNominal > 0) then
    //calc load from P
  begin
    pOutput.Load := (pOutput.Power / pOutput.PowerNominal) * 100;
  end
  else if (pOutput.Load = UPSinfo_UnkVal) and (pOutput.CurrentNominal > 0) then
    //calc load from I
  begin
    pOutput.Load := (pOutput.Current / pOutput.CurrentNominal) * 100;
  end;

end;

procedure GetNUTtoBatt(var pData: string; var pBatt: TUPSbatteryType);
var
  s: string;
begin
  pBatt.Charge := GetNUTdbl(pData, 'battery.charge');
  pBatt.Runtime := GetNUTdbl(pData, 'battery.runtime');
  pBatt.Voltage := GetNUTdbl(pData, 'battery.voltage');
  pBatt.VoltageNominal := GetNUTdbl(pData, 'battery.voltage.nominal');
  pBatt.Replaced := GetNUTValue(pData, 'battery.date');
  if (UpperCase(pBatt.Replaced) = 'NOT SET') or (pBatt.Replaced = '') then
    pBatt.Replaced := GetNUTValue(pData, 'battery.mfr.date');

  s := UpperCase(GetNUTValue(pData, 'battery.status'));
  if (s = 'OK') or (s = '') then //status given (or not) but dwell on
  begin
    s := GetNUTValue(pData, 'ups.status');
    if Pos('RB', s) > 0 then
    begin
      pBatt.Status := UPS_BattNeedRepl;
    end
    else if Pos('OL', s) > 0 then
    begin
      if Pos('CHRG', s) > 0 then
        pBatt.Status := UPS_BattCharging
      else
        pBatt.Status := UPS_BattStatusOk;
    end
    else if Pos('OB', s) > 0 then
    begin
      pBatt.Status := UPS_BattDisChrg;
    end;
  end
  else
  begin  //status given but not ok
    pBatt.Status := UPS_BattNeedRepl;
  end;

end;

{ TUPSinfoNUT }

procedure TUPSinfoNUTthread.resetError;
begin
  FErrorCode := UPSinfo_ResOK;
  FErrorDesc := '';
  FStatus := '';
end;

procedure TUPSinfoNUTthread.clearDevice;
begin
  FDevice.Status := UPS_StatusUnknown;
  FDevice.Temperature := UPSinfo_UnkVal;
  FDevice.Timer := UPSinfo_UnkVal;
  FDevice.Id := '';
  FDevice.Desc := '';
  FDevice.Firmware := '';
  FDevice.MFR := '';
  FDevice.Model := '';
  FDevice.Serial := '';
  FDevice.StatusRaw := '';
end;

procedure TUPSinfoNUTthread.clearInput;
begin
  FInput.Voltage := UPSinfo_UnkVal;
  FInput.VoltageNominal := UPSinfo_UnkVal;
  FInput.Current := UPSinfo_UnkVal;
  FInput.CurrentNominal := UPSinfo_UnkVal;
  FInput.Frequency := UPSinfo_UnkVal;
  Finput.Load := UPSinfo_UnkVal;
end;

procedure TUPSinfoNUTthread.clearOutput;
begin
  FOutput.Frequency := UPSinfo_UnkVal;
  FOutput.CurrentNominal := UPSinfo_UnkVal;
  FOutput.Current := UPSinfo_UnkVal;
  FOutput.Voltage := UPSinfo_UnkVal;
  FOutput.VoltageNominal := UPSinfo_UnkVal;
  FOutput.Load := UPSinfo_UnkVal;
  FOutput.Power := UPSinfo_UnkVal;
  FOutput.PowerNominal := UPSinfo_UnkVal;
end;

procedure TUPSinfoNUTthread.clearBattery;
begin
  FBattery.Charge := UPSinfo_UnkVal;
  FBattery.Replaced := '';
  FBattery.Runtime := UPSinfo_UnkVal;
  FBattery.Status := UPS_BattStatusUnk;
  FBattery.Voltage := UPSinfo_UnkVal;
  FBattery.VoltageNominal := UPSinfo_UnkVal;
end;

procedure TUPSinfoNUTthread.doStatus(stat: string);
begin
  FStatus := stat;
  Synchronize(@runStatus);
end;

procedure TUPSinfoNUTthread.runStatus;
begin
  frmWindow.statusText := FStatus;
  frmWindow.ShowStatus;
end;

procedure TUPSinfoNUTthread.doData;
begin
  CloneDevice(@FDevice, @frmWindow.statDevice);
  CloneInput(@FInput, @frmWindow.statInput);
  CloneOutput(@FOutput, @frmWindow.statOutput);
  CloneBattery(@FBattery, @frmWindow.statBattery);
  frmWindow.ShowData;
end;

constructor TUPSinfoNUTthread.Create;
begin
  inherited Create(True);    //suspend on creation
  FreeOnTerminate := True;   //self terminate
  FLocalIP := cAnyHost;
  FLocalPort := cAnyPort;
  FRemoteIP := cAnyHost;
  FRemotePort := cAnyPort;
  FRemoteUser := '';
  FRemotePass := '';
  FDeviceId := '';
  FStatus := '';
  Fsock := TTCPBlockSocket.Create;
  Fsock.Family := SF_IP4;
  Fsock.PreferIP4 := True;

  clearDevice;
  clearInput;
  clearOutput;
  clearBattery;
end;

destructor TUPSinfoNUTthread.Destroy;
begin
  doStatus('TUPSinfoNUTthread.Destroy');
  inherited Destroy;
  Fsock.AbortSocket;
  Fsock.Free;
end;

procedure TUPSinfoNUTthread.Execute;
var
  execstat: TUPSinfoNUTstatusType;
  tickstat: longword; //tick when status begins
  s: string;
  i: integer;
begin
  resetError;
  //doStatus('OK Bind ' + FLocalIP + ':' + FLocalPort);
  doStatus('TUPSinfoNUTthread.Execute');
  execstat := Exec0_Pre;
  while (not Terminated) do
  begin
    case execstat of
      Exec0_Pre:
      begin
        doStatus(TickStr + ':TUPSinfoNUTthread.Exec0_Pre');
        tickstat := TickNow;

        if FRemotePort = '' then
          FRemotePort := '0';
        if FRemoteIP = '' then
          FRemoteIP := cAnyHost;

        if (FRemoteIP = cAnyHost) or (FRemotePort = '0') then
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread Remote ip/port not valid: ' +
            FRemoteIP + ':' + FRemotePort);
          execstat := Exec12_Err;
          FErrorCode := UPSinfo_ResErr;
          FErrorDesc := 'Remote ip/port not valid: ' + FRemoteIP + ':' + FRemotePort;
          Exit;
        end;
        if Fsock = nil then
        begin
          Fsock := TTCPBlockSocket.Create;
        end;
        Fsock.Family := SF_IP4;
        Fsock.PreferIP4 := True;
        execstat := Exec1_Bind;
      end;
      //---------------
      Exec1_Bind:
      begin
        tickstat := TickNow;
        doStatus(TickStr + ':TUPSinfoNUTthread.Exec1_Bind');
        if FLocalPort = '' then
          FLocalPort := '0';
        if FLocalIP = '' then
          FLocalIP := cAnyHost;

        Fsock.Bind(FLocalIP, FLocalPort);
        if not (Fsock.LastError = 0) then
        begin
          FErrorCode := Fsock.LastError;
          FErrorDesc := Fsock.LastErrorDesc;
          doStatus(TickStr + ':TUPSinfoNUTthread Bind tcpsock error: ' +
            IntToStr(FErrorCode) + ' ' + FErrorDesc);
          execstat := Exec12_Err;
        end
        else
        begin
          resetError;
          doStatus(TickStr + ':TUPSinfoNUTthread Bind to ' +
            Fsock.GetLocalSinIP + ':' + IntToStr(Fsock.GetLocalSinPort));
          tickstat := TickNow;
          execstat := Exec2_Conn;
        end;
      end;//end Exec1_Bind
      //------------------
      Exec2_Conn:
      begin
        tickstat := TickNow;
        doStatus(TickStr + ':TUPSinfoNUTthread.Exec2_Conn');
        Fsock.Connect(FRemoteIP, FRemotePort);
        if not (Fsock.LastError = 0) then
        begin
          FErrorCode := Fsock.LastError;
          FErrorDesc := Fsock.LastErrorDesc;
          doStatus(TickStr + ':TUPSinfoNUTthread Connect tcpsock error: ' +
            IntToStr(FErrorCode) + ' ' + FErrorDesc);
          execstat := Exec12_Err;
        end
        else
        begin
          resetError;
          doStatus(TickStr + ':TUPSinfoNUTthread Connect to ' +
            Fsock.GetRemoteSinIP + ':' + IntToStr(Fsock.GetRemoteSinPort));
          tickstat := TickNow;
          execstat := Exec3_LogUsrS;
        end;
      end;//end Exec2_Conn;
      //-------------------
      Exec3_LogUsrS:
      begin
        if (FRemotePass = '') or (FRemoteUser = '') then
        begin
          //skip login
          doStatus(TickStr + ':TUPSinfoNUTthread Login skip, user/password is empty');
          tickstat := TickNow;
          execstat := Exec7_ReqInitS;
        end
        else
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread Login send');
          Fsock.SendString('USERNAME ' + FRemoteUser + LineEnding);
          tickstat := TickNow;
          execstat := Exec4_LogUsrR;
        end;
      end;//end Exec3_LogUsrS
      //---------------------
      Exec4_LogUsrR:
      begin
        if (Fsock.WaitingData > 0) then
        begin
          s := Fsock.RecvPacket(2000);
          if Pos('OK', s) > 0 then
          begin//user ok, send pass
            tickstat := TickNow;
            execstat := Exec5_LogPasS;
          end
          else
          begin
            //user not valid, try without
            doStatus(TickStr + ':TUPSinfoNUTthread Login error, user not valid: ' +
              FRemoteUser);
            tickstat := TickNow;
            execstat := Exec7_ReqInitS;
          end;
        end
        else if (TickElapsed(tickstat) > 10) then //no data check timeout
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread timeout, send login again');
          execstat := Exec3_LogUsrS;
        end;
        { TODO : introduce counter for timeout, then should goto error }
      end;//end Exec4_LogUsrR
      //---------------------
      Exec5_LogPasS:
      begin
        doStatus(TickStr + ':TUPSinfoNUTthread Password send');
        Fsock.SendString('PASSWORD ' + FRemotePass + LineEnding);
        tickstat := TickNow;
        execstat := Exec6_LogPasR;
      end;//end Exec5_LogPasS
      //---------------------
      Exec6_LogPasR:
      begin
        if (Fsock.WaitingData > 0) then
        begin
          s := Fsock.RecvPacket(2000);
          if Pos('OK', s) > 0 then
          begin//password ok
            doStatus(TickStr + ':TUPSinfoNUTthread Login OK');
            tickstat := TickNow;
            execstat := Exec7_ReqInitS;
          end
          else
          begin
            //password not valid, try without
            doStatus(TickStr + ':TUPSinfoNUTthread Password error, not valid.');
            tickstat := TickNow;
            execstat := Exec7_ReqInitS;
          end;
        end
        else if (TickElapsed(tickstat) > 10) then //no data check timeout
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread timeout, send password again');
          execstat := Exec5_LogPasS;
        end;
        { TODO : introduce counter for timeout, then should goto error }
      end;//end Exec6_LogPasR
      //---------------------
      Exec7_ReqInitS:
      begin
        doStatus(TickStr + ':TUPSinfoNUTthread Req LIST UPS');
        Fsock.SendString('LIST UPS' + LineEnding);
        tickstat := TickNow;
        execstat := Exec8_ReqInitR;
      end; //end Exec7_ReqInitS
      //-----------------------
      Exec8_ReqInitR:
      begin
        if (Fsock.WaitingData > 0) then
        begin
          s := Fsock.RecvPacket(2000);
          if (Pos('BEGIN LIST UPS', s) > 0) then
          begin
            doStatus(TickStr + ':TUPSinfoNUTthread Received LIST UPS: ' + s);
            s := Trim(GetBetween('BEGIN LIST UPS', 'END LIST ', s));
            i := Pos('UPS ', s);
            if i > 0 then
            begin  //get first ups from list
              s := Trim(s.Substring(i + 3)); //-1 + lenght 'UPS '
              i := Pos(' ', s);
              if i > 0 then
                FDevice.Id := Trim(s.Substring(0, i));
              FDevice.Desc := Trim(GetBetween('"', '"', s.Substring(i)));
              doStatus(TickStr + ':TUPSinfoNUTthread UPS id: ' +
                FDevice.Id + ', desc: ' + FDevice.Desc);
            end;
            { TODO : should check whole list for preset id like in FdeviceId }

            if (FDeviceId = '') then
            begin //there was not ups id
              FDeviceId := FDevice.Id;
            end
            else if (FDeviceId <> FDevice.Id) then
            begin //id preset is diffrent from received
              doStatus(TickStr + ':TUPSinfoNUTthread UPS id: ' +
                FDevice.Id + ' is diffrent from preset: ' + FDeviceId);
              FDeviceId := FDevice.Id; //not anymore
            end;

            tickstat := TickNow;
            execstat := Exec9_ReqListS;
          end
          else
          begin
            doStatus(TickStr + ':TUPSinfoNUTthread not LIST UPS, req again');
            execstat := Exec7_ReqInitS;
          end;

        end
        else if (TickElapsed(tickstat) > 10) then //no data check timeout
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread timeout, Req LIST UPS again');
          execstat := Exec7_ReqInitS;
        end;
        { TODO : introduce counter for timeout, then should goto error }
      end;//end Exec8_ReqInitR
      //----------------------
      Exec9_ReqListS:
      begin
        doStatus(TickStr + ':TUPSinfoNUTthread Req LIST VAR');
        Fsock.SendString('LIST VAR ' + FDeviceId + LineEnding);
        tickstat := TickNow;
        execstat := Exec10_ReqListR;
      end;//end Exec9_ReqListS
      //----------------------
      Exec10_ReqListR:
      begin
        if (Fsock.WaitingData > 0) then
        begin
          s := Fsock.RecvPacket(2000);
          if (Pos('BEGIN LIST VAR', s) > 0) then
          begin
            //process var to records
            GetNUTtoDevice(s, FDevice);
            GetNUTtoInput(s, FInput);
            GetNUTtoOutput(s, FOutput);
            GetNUTtoBatt(s, FBattery);

            doStatus(TickStr + ':TUPSinfoNUTthread Received LIST VAR, status: ' +
              GetStatDescDevice(FDevice.Status) + ', raw: ' +
              FDevice.StatusRaw + ', timer: ' + IntToStr(FDevice.Timer) +
              '. Voltage: input: ' + FloatToStr(FInput.Voltage) +
              ', output: ' + FloatToStr(FOutput.Voltage) + '. Load: ' +
              FloatToStr(FOutput.Load) + ', battery: ' +
              GetStatDescBatt(FBattery.Status));
            //doStatus(TickStr + ':TUPSinfoNUTthread LIST VAR:'+ s ); //for debug

            Synchronize(@doData);

            tickstat := TickNow;
            execstat := Exec11_IdleConn;
          end
          else
          begin
            doStatus(TickStr + ':TUPSinfoNUTthread not LIST VAR, req again');
            execstat := Exec9_ReqListS;
          end;
        end
        else if (TickElapsed(tickstat) > 10) then //no data check timeout
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread timeout, Req LIST VAR again');
          execstat := Exec9_ReqListS;
        end;
        { TODO : introduce counter for timeout or control to change device status after OB }
      end;//end Exec10_ReqListR
      //-----------------------
      Exec11_IdleConn:
      begin
        if (FDevice.Status = UPS_StatusShutdown) or (FDevice.Status = UPS_StatusOB) then
        begin
          i := 2;
        end
        else
        begin
          i := 15;
        end;

        if (integer(TickElapsed(tickstat)) > i) then
        begin
          doStatus(TickStr + ':TUPSinfoNUTthread Exec11_IdleConn tmout: ' + IntToStr(i));
          execstat := Exec9_ReqListS;
        end;
        { TODO : some logic to controll state change and reaction ex. OL >OB then conn lost}

      end;//end Exec11_IdleConn

      //---------------------
      Exec12_Err:
      begin
        if (TickElapsed(tickstat) > 60) then
        begin
          doStatus('TUPSinfoNUTthread.Exec12_Err -> Exec0_Pre');
          execstat := Exec0_Pre;
          if Fsock <> nil then
            FreeAndNil(Fsock);
        end;
      end;//end Exec12_Err
      else
      begin
        //unknown status
        doStatus('TUPSinfoNUTthread.Execute status go to Exec12_Err');
        tickstat := TickNow;
        execstat := Exec12_Err;
        Sleep(500);
      end;

    end;//end case



    Sleep(100);
  end;//end main execute loop
end;

procedure TUPSinfoNUTthread.SetLocal(ip, port: string);
begin
  FLocalIP := ip;
  FLocalPort := port;
end;

procedure TUPSinfoNUTthread.SetRemote(ip, port: string);
begin
  FRemoteIP := ip;
  FRemotePort := port;
end;

procedure TUPSinfoNUTthread.SetCredentials(user, pass: string);
begin
  FRemoteUser := user;
  FRemotePass := pass;
end;

procedure TUPSinfoNUTthread.SetDeviceId(id: string);
begin
  FDeviceId := id;
end;


end.
