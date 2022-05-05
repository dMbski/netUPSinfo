unit nethelper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BlckSock, synsock, synaip,
  synaUtil, upshelper, Dialogs;

const

  NH_ResOK = 0;
  NH_ResError = 1;

  IPprot_UDP = 17;
  IPprot_TCP = 6;
  IPprot_Any = 0; //dummy


type

  TUPSNetServiceType = (
    UPS_Any,
    UPS_PowerMaster,
    UPS_NUT
    );

  TNetHelperActionType = (
    NH_ActionRun,        //normal loop
    NH_ActionTestConn,   //check connection bind, connect, login then return
    NH_ActionListUPS     //powermaster receive first transmission, NUT cmd list ups, return
    );

  TNetHelperStatusType = (
    NH_Net_0Pre,       {precheck and initialise}
    NH_Net_1Bind,      {to bind}
    NH_Net_2Conn,      {to connect}
    NH_Net_3Login,     {to login }
    NH_Net_4LoginOK,   {after login}
    NH_Net_5ReqInit,   {to request ups name if need to}
    NH_Net_6WaitInit,  {to wait for packet with name}
    NH_Net_7ReqVar,    {to request Vars}
    NH_Net_8WaitVar,   {to wait for Vars}
    NH_Net_9Idle       {to do nothing, wait for some timeout}
    );


  { TSocketHelper }
  TSocketHelper = class(TObject)
  private
    FSocketProt: integer;
    FErrorCode: integer;
    FErrorDesc: string;
    FUDPsock: TUDPBlockSocket;
    FTCPsock: TTCPBlockSocket;
    function createSockets(forced: boolean = False): boolean;
    function checkSockets: boolean;
    function checkProtocol: boolean;
    procedure resetError;

  public
    constructor Create(ipprotocol: integer = IPprot_Any);
    destructor Destroy; override;

    function Bind(localip, localport: string): boolean;
    function Connect(remip, remport: string): boolean;
    function WaitigData: integer;
    function ReceivePacket(timeout: integer = 1000): string;
    procedure ResetSockets;
    procedure SendString(str: string);
  published
    property Protocol: integer read FSocketProt write FSocketProt;
    property LastError: integer read FErrorCode;
    property LastErrorDesc: string read FErrorDesc;
  end;



  { TNetHelper }

  TNetHelper = class(TThread)
    destructor Destroy; override;

  public
    constructor Create;
    procedure SetAction(action: TNetHelperActionType = NH_ActionRun);
    procedure Execute; override;
    procedure SetLocal(ip, port: string);
    procedure SetRemote(ip, port: string);
    procedure SetCredentials(user, pass: string);
    procedure SetUPSdeviceid(id: string); {sets ups.id}
  private
    FLocalIP: string;
    FLocalPort: string;
    FRemoteIP: string;
    FRemotePort: string;
    FRemoteUser: string;
    FRemotePass: string;
    FErrorCode: integer;
    FErrorDesc: string;
    FStatusDesc: string;
    FUPStype: TUPSNetServiceType;
    FAction: TNetHelperActionType;
    FnetStatus: TNetHelperStatusType;
    FUPS: TUPSdeviceHelper;
    FSocketHlp: TSocketHelper;
    procedure setUPStype(AValue: TUPSNetServiceType);
    {sets FErrorCode=NH_ResOK and FErrorDesc=''  }
    procedure resetError;
    procedure doStatus(s: string);
    procedure runStatus;
  published
    property UPS: TUPSdeviceHelper read FUPS write FUPS;
    property UPStype: TUPSNetServiceType read FUPStype write setUPStype;
    property ErrorDesc: string read FErrorDesc;
    property LastError: integer read FErrorCode;
  end;


implementation

uses mainfrm;

{ TSocketHelper }

procedure TSocketHelper.resetError;
begin
  FErrorCode := NH_ResOK;
  FErrorDesc := '';
end;

function TSocketHelper.createSockets(forced: boolean): boolean;
begin
  Result := True;
  case FSocketProt of
    IPprot_TCP:
    begin
      if (FTCPsock <> nil) and forced then
      begin
        //destroy socket tcp
        FTCPsock.AbortSocket;
        FTCPsock.Free;
      end
      else if FTCPsock <> nil then
      begin
        //socket exists, exit
        Exit;
      end;

      //create then tcp
      try
        FTCPsock := TTCPBlockSocket.Create;
      except
        Result := False;
        Exit;
      end;
      FTCPsock.Family := SF_IP4;
      FTCPsock.PreferIP4 := True;
    end;
    IPprot_UDP:
    begin
      if (FUDPsock <> nil) and forced then
      begin
        //destroy socket udp
        FUDPsock.AbortSocket;
        FUDPsock.Free;
      end
      else if FUDPsock <> nil then
      begin
        //socket exists, exit
        Exit;
      end;

      //create then udp
      try
        FUDPsock := TUDPBlockSocket.Create;
      except
        Result := False;
        Exit;
      end;
      FUDPsock.Family := SF_IP4;
      FUDPsock.PreferIP4 := True;
    end;
    else
    begin
      //general error, when no prot udp/tcp is set
      Result := False;
    end;
  end;
end;

function TSocketHelper.checkSockets: boolean;
begin
  Result := True;
  case FSocketProt of
    IPprot_TCP:
    begin
      if FTCPsock = nil then
      begin
        FErrorCode := NH_ResError;
        FErrorDesc := 'TCP Socket not created.';
        Result := False;
      end;
    end;
    IPprot_UDP:
    begin
      if FUDPsock = nil then
      begin
        Result := False;
        FErrorCode := NH_ResError;
        FErrorDesc := 'UDP Socket not created.';
      end;
    end;
    else
    begin
      Result := False;
      FErrorCode := NH_ResError;
      FErrorDesc := 'CheckSockets: IP protocol tcp/udp not specified.';
    end;
  end;
end;

function TSocketHelper.checkProtocol: boolean;
begin
  Result := True;
  ResetError;
  if not ((FSocketProt = IPprot_TCP) or (FSocketProt = IPprot_UDP)) then
  begin
    Result := False;
    FErrorCode := NH_ResError;
    FErrorDesc := 'No IP protocol set (UDP or TCP?)';
  end;
end;

constructor TSocketHelper.Create(ipprotocol: integer);
begin
  FSocketProt := ipprotocol;
  FErrorCode := NH_ResOK;
  FErrorDesc := '';
  FUDPsock := nil;
  FTCPsock := nil;
end;

destructor TSocketHelper.Destroy;
begin
  inherited Destroy;
  ResetSockets;
end;

function TSocketHelper.Bind(localip, localport: string): boolean;
var
  sinip: string;
  sinport: integer;
begin
  ResetError;
  Result := False;

  if checkProtocol = False then
    Exit;

  Result := CreateSockets(True);

  if not Result then
  begin
    FErrorCode := NH_ResError;
    FErrorDesc := 'Bind: Error when socket.create.';
    Exit;
  end;

  case FSocketProt of
    IPprot_TCP:
    begin
      FTCPsock.Bind(localip, localport);
      if not (FTCPsock.LastError = 0) then
      begin
        FErrorCode := FTCPsock.LastError;
        FErrorDesc := FTCPsock.LastErrorDesc;
      end
      else
      begin
        sinip := FTCPsock.GetLocalSinIP;
        sinport := FTCPsock.GetLocalSinPort;
      end;
    end;
    IPprot_UDP:
    begin
      FUDPsock.Bind(localip, localport);
      if not (FUDPsock.LastError = 0) then
      begin
        FErrorCode := FUDPsock.LastError;
        FErrorDesc := FUDPsock.LastErrorDesc;
      end
      else
      begin
        sinip := FUDPsock.GetLocalSinIP;
        sinport := FUDPsock.GetLocalSinPort;
      end;
    end;
  end;

  if (FErrorCode <> NH_ResOK) then
  begin
    FErrorDesc := 'Bind error: ' + IntToStr(FErrorCode) + '. ' + FErrorDesc;
    Exit;
  end;

  FErrorDesc := 'LocalSin: ' + sinip + ':' + IntToStr(sinport);

  if (StrToIntDef(localport, 0) <> 0) and (StrToIntDef(localport, 0) <> sinport) then
  begin
    //error with port
    FErrorCode := NH_ResError;
    FErrorDesc := 'Mismatch between the desired port #' + localport +
      ' and set one #' + IntToStr(sinport) + LineEnding + FErrorDesc;
  end;

  if (localip <> cAnyHost) and (localip <> sinip) then
  begin
    //error with ip
    FErrorCode := NH_ResError;
    FErrorDesc := 'Mismatch between the desired IP address: ' + localip +
      ' and set one: ' + sinip + LineEnding + FErrorDesc;
  end;

  if (FErrorCode = NH_ResOK) then
    Result := True;

end;

function TSocketHelper.Connect(remip, remport: string): boolean;
var
  sinip: string;
  sinport: integer;
begin
  ResetError;
  Result := False;

  if checkProtocol = False then
  begin
    FErrorDesc := 'Connect: ' + FErrorDesc;
    Exit;
  end;

  Result := CreateSockets(False);
  if not Result then
  begin
    FErrorCode := NH_ResError;
    FErrorDesc := 'Connect: Error when socket.create.';
    Exit;
  end;

  case FSocketProt of
    IPprot_TCP:
    begin
      FTCPsock.Connect(remip, remport);
      if not (FTCPsock.LastError = 0) then
      begin
        FErrorCode := FTCPsock.LastError;
        FErrorDesc := FTCPsock.LastErrorDesc;
      end
      else
      begin
        sinip := FTCPsock.GetRemoteSinIP;
        sinport := FTCPsock.GetRemoteSinPort;
      end;
    end;
    IPprot_UDP:
    begin
      FUDPsock.Connect(remip, remport);
      if not (FUDPsock.LastError = 0) then
      begin
        FErrorCode := FUDPsock.LastError;
        FErrorDesc := FUDPsock.LastErrorDesc;
      end
      else
      begin
        sinip := FUDPsock.GetRemoteSinIP;
        sinport := FUDPsock.GetRemoteSinPort;
      end;
    end;
  end;

  if (FErrorCode <> NH_ResOK) then
  begin
    FErrorDesc := 'Connect error: ' + IntToStr(FErrorCode) + '. ' + FErrorDesc;
    Exit;
  end;

  if (StrToIntDef(remport, 0) <> 0) and (StrToIntDef(remport, 0) <> sinport) then
  begin
    //error with port
    FErrorCode := NH_ResError;
    FErrorDesc := 'Mismatch between the desired port #' + remport +
      ' and connected to #' + IntToStr(sinport) + LineEnding + FErrorDesc;
  end;

  if (remip <> cAnyHost) and (remip <> sinip) then
  begin
    //error with ip
    FErrorCode := NH_ResError;
    FErrorDesc := 'Mismatch between the desired IP address: ' + remip +
      ' and connected to: ' + sinip + LineEnding + FErrorDesc;
  end;

  if (FErrorCode = NH_ResOK) then
    Result := True;
end;

function TSocketHelper.WaitigData: integer;
begin
  ResetError;

  Result := 0;
  if checkProtocol = False then
  begin
    FErrorDesc := 'WaitingData: ' + FErrorDesc;
    Exit;
  end;
  if CheckSockets = False then
  begin
    FErrorDesc := 'WaitingData: ' + FErrorDesc;
    Exit;
  end;
  case FSocketProt of
    IPprot_TCP:
    begin
      Result := FTCPsock.WaitingData;
    end;
    IPprot_UDP:
    begin
      Result := FUDPsock.WaitingData;
    end;
  end;
end;

function TSocketHelper.ReceivePacket(timeout: integer): string;
begin
  ResetError;
  Result := '';
  if checkProtocol = False then
  begin
    FErrorDesc := 'ReceivePacket: ' + FErrorDesc;
    Exit;
  end;

  if CheckSockets = False then
  begin
    FErrorDesc := 'ReceivePacket: ' + FErrorDesc;
    Exit;
  end;

  case FSocketProt of
    IPprot_TCP:
    begin
      Result := FTCPsock.RecvPacket(timeout);
      FErrorCode := FTCPsock.LastError;
      FErrorDesc := FTCPsock.LastErrorDesc;
    end;
    IPprot_UDP:
    begin
      Result := FUDPsock.RecvPacket(timeout);
      FErrorCode := FUDPsock.LastError;
      FErrorDesc := FUDPsock.LastErrorDesc;
    end;
  end;

  if FErrorCode = WSAETIMEDOUT then    //this error is not error ;-)
  begin
    FErrorCode := NH_ResOK;
    FErrorDesc := '';
  end
  else if FErrorCode <> 0 then
  begin
    FErrorDesc := 'ReceivePacket: Socket error #' + IntToStr(FErrorCode) +
      '. ' + FErrorDesc;
    FErrorCode := NH_ResError;
  end;

end;

procedure TSocketHelper.ResetSockets;
begin
  if FUDPsock <> nil then
  begin
    FUDPsock.AbortSocket;
    FUDPsock.Free;
    FUDPsock := nil;
  end;
  if FTCPsock <> nil then
  begin
    FTCPsock.AbortSocket;
    FTCPsock.Free;
    FTCPsock := nil;
  end;
end;

procedure TSocketHelper.SendString(str: string);
begin
  ResetError;
  if checkProtocol = False then
  begin
    FErrorDesc := 'SendString: ' + FErrorDesc;
    Exit;
  end;

  if CheckSockets = False then
  begin
    FErrorDesc := 'SendString: ' + FErrorDesc;
    Exit;
  end;

  case FSocketProt of
    IPprot_TCP:
    begin
      FTCPsock.SendString(str);
      FErrorCode := FTCPsock.LastError;
      FErrorDesc := FTCPsock.LastErrorDesc;
    end;
    IPprot_UDP:
    begin
      FUDPsock.SendString(str);
      FErrorCode := FUDPsock.LastError;
      FErrorDesc := FUDPsock.LastErrorDesc;
    end;
  end;

  if FErrorCode <> 0 then
  begin
    FErrorDesc := 'SendString: Socket error #' + IntToStr(FErrorCode) +
      '. ' + FErrorDesc;
    FErrorCode := NH_ResError;
  end;

end;


{ TNetHelper }

destructor TNetHelper.Destroy;
begin
  inherited Destroy;
  FUPS.Free;
  FSocketHlp.Free;
end;

constructor TNetHelper.Create;
begin
  inherited Create(True);     //suspend on creation
  FreeOnTerminate := False;   //no terminate cos multiple actions

  FUPS := TUPSdeviceHelper.Create;
  FSocketHlp := TSocketHelper.Create;

  FLocalIP := cAnyHost;
  FLocalPort := cAnyPort;
  FRemoteIP := cAnyHost;
  FRemotePort := cAnyPort;
  FRemoteUser := '';
  FRemotePass := '';
  FErrorDesc := '';
  FErrorCode := NH_ResOK;
  FUPStype := UPS_Any;
  FAction := NH_ActionRun;
  FnetStatus := NH_Net_9Idle;
  ShowMessage('TNetHelper.Create ends');
end;

procedure TNetHelper.SetAction(action: TNetHelperActionType);
begin
  resetError;
  FAction := action;
  FnetStatus := NH_Net_9Idle;
end;

procedure TNetHelper.Execute;
var
  br: boolean;
  ss: string;
  p: integer;

  tickStart: int64;
  tickStatus: int64;
  statuscount: integer;

  function tickNow: int64;
  begin
    //system ticks ms
    Result := GetTick;
  end;

  function tickElapsedSec(tthen, tnow: int64): int64;
  begin
    Result := 0;
    if tnow > tthen then
      Result := (tnow - tthen) div 1000
    else
      Result := (tthen - tnow) div 1000;
  end;

  function loginNUT: boolean;
  var
    s: string;
  begin
    Result := True;
    resetError;
    FSocketHlp.SendString('USERNAME ' + FRemoteUser + LineEnding);
    Sleep(500);
    s := FSocketHlp.ReceivePacket(2000);
    if Pos('OK', s) = 0 then
    begin
      FErrorCode := NH_ResError;
      FErrorDesc := 'Execute: Login user failed with: ' + s;
    end
    else
    begin
      FSocketHlp.SendString('PASSWORD ' + FRemotePass + LineEnding);
      Sleep(500);
      s := FSocketHlp.ReceivePacket(2000);
      if Pos('OK', s) = 0 then
      begin
        FErrorCode := NH_ResError;
        FErrorDesc := 'Execute: Login pass failed with: ' + s;
      end;
    end;
    if FErrorCode <> NH_ResOK then
      Result := False;
  end;

begin
  resetError;
  FSocketHlp.ResetSockets;
  FnetStatus := NH_Net_0Pre;
  tickStart := tickNow;
  tickStatus := tickNow;
  statuscount := 0;
  //main running event
  //checking
  case FUPStype of
    UPS_PowerMaster:
    begin
      p := IPprot_UDP;
    end;
    UPS_NUT:
    begin
      p := IPprot_TCP;
    end;
    else
    begin
      FErrorCode := NH_ResError;
      FErrorDesc := 'Execute: UPS type not configured';
      Exit;
    end;
  end;
  FSocketHlp.Protocol := p;

  if FUPStype = UPS_NUT then
  begin
    if (not IsIP(FRemoteIP)) or (FRemoteIP = cAnyHost) then
    begin
      FErrorDesc := 'Execute: Remote NUTsrv address is not valid: ' + FRemoteIP;
      FErrorCode := NH_ResError;
      Exit;
    end;
  end;
  //checking end
  FnetStatus := NH_Net_1Bind;
  statuscount := 0;

  while (not Terminated) do
  begin

    case FnetStatus of
      NH_Net_1Bind:
      begin
        if tickElapsedSec(tickStatus, tickNow) > 3 then
        begin
          tickStatus := tickNow;
          statuscount := statuscount + 1;
          br := FSocketHlp.Bind(FLocalIP, FLocalPort);
          if br then
          begin
            //promote to next status
            FnetStatus := NH_Net_2Conn;
            tickStatus := tickNow - 10000;
            statuscount := 0;
            doStatus('OK Bind ' + FLocalIP + ':' + FLocalPort);
          end
          else
          begin
            if statuscount > 7 then
            begin
              FErrorCode := NH_ResError;
              FErrorDesc := 'Execute: TSocketHelper. Bind error. ' +
                FSocketHlp.LastErrorDesc;
              Exit;
            end;
          end;
        end;
      end;
      NH_Net_2Conn:
      begin
        if tickElapsedSec(tickStatus, tickNow) > 5 then
        begin
          tickStatus := tickNow;
          statuscount := statuscount + 1;
          br := FSocketHlp.Connect(FRemoteIP, FRemotePort);
          if br then
          begin
            //promote to next status
            FnetStatus := NH_Net_3Login;
            tickStatus := tickNow - 5000;
            statuscount := 0;
            doStatus('OK Connect ' + FRemoteIP + ':' + FRemotePort);
          end
          else
          begin
            if statuscount > 4 then
            begin
              FErrorCode := NH_ResError;
              FErrorDesc := 'Execute: TSocketHelper.Connect error. ' +
                FSocketHlp.LastErrorDesc;
              Exit;
            end;
          end;
        end;
      end;
      NH_Net_3Login:
      begin
        if (FUPStype = UPS_NUT) and (FRemoteUser <> '') and (FRemotePass <> '') then
        begin //only NUT may need login
          if tickElapsedSec(tickStatus, tickNow) > 5 then
          begin
            tickStatus := tickNow;
            statuscount := statuscount + 1;
            br := loginNUT;
            if br then
            begin
              //promote to next status
              FnetStatus := NH_Net_4LoginOK;
              tickStatus := tickNow;
              statuscount := 0;
            end
            else
            begin
              if statuscount > 4 then
              begin
                FErrorCode := NH_ResError;
                //FErrorDesc; //loginnut fill in this
                Exit;
              end;
            end;
          end;
        end
        else //not NUT or no credentials
        begin
          FnetStatus := NH_Net_4LoginOK;
          tickStatus := tickNow;
          statuscount := 0;
        end;
      end;
      NH_Net_4LoginOK:
      begin
        doStatus('OK Login');
        if (FAction = NH_ActionTestConn) then
        begin
          resetError;
          Exit;
        end;
        FnetStatus := NH_Net_5ReqInit;
        tickStatus := tickNow;
        tickStart := tickNow;
        statuscount := 0;

      end;
      NH_Net_5ReqInit:
      begin
        //no reset statuscount becouse waitinit
        if (FUPStype = UPS_NUT) then
        begin
          if (FUPS.DevId = '') or (FAction = NH_ActionListUPS) then
          begin
            doStatus('OK SendString LIST UPS');
            FSocketHlp.SendString('LIST UPS' + LineEnding);
            tickStatus := tickNow;
            FnetStatus := NH_Net_6WaitInit;
          end
          else
          begin //no need init
            //promote to next+1 status
            FnetStatus := NH_Net_7ReqVar;
            tickStatus := tickNow;
            tickStart := tickNow;
            statuscount := 0;
          end;
        end
        else
        begin //not NUT, just wait
          //promote to next status
          FnetStatus := NH_Net_6WaitInit;
          tickStatus := tickNow;
        end;
      end;
      NH_Net_6WaitInit:
      begin
        if FSocketHlp.WaitigData > 0 then
        begin //some data
          br := False;
          ss := FSocketHlp.ReceivePacket(2000);
          if (FUPStype = UPS_NUT) then
          begin
            if (FUPS.ProcessNUTinit(ss)) then
            begin
              //init NUT ok
              br := True;
            end
            else
            begin
              //init NUT data error
              FnetStatus := NH_Net_5ReqInit;
            end;
          end
          else //(FUPStype = UPS_PowerMaster)
          begin
            if (FUPS.ProcessPMinit(ss)) then
            begin
              //init PM+ ok
              br := True;
            end
            else
            begin
              //init PM+ data error
            end;

          end;

          if br then
          begin
            doStatus('OK init UPS');
            if (FAction = NH_ActionListUPS) then
            begin
              resetError;
              //ShowMessage('dbg listups ok');
              Exit;
            end;
            //promote to next status
            FnetStatus := NH_Net_7ReqVar;
            tickStatus := tickNow - 30000;
            tickStart := tickNow;
            statuscount := 0;
          end
          else
          begin
            statuscount := statuscount + 1;
          end;
        end
        else
        begin
          //no data yet
          if tickElapsedSec(tickStatus, tickNow) > 1 then
          begin
            statuscount := statuscount + 1;
            tickStatus := tickNow;
            if (FUPStype = UPS_NUT) and ((statuscount mod 5) = 0) then
            begin
              //resend list
              FnetStatus := NH_Net_5ReqInit;
            end;
          end;
        end;

        if (statuscount > 20) or (tickElapsedSec(tickStart, tickNow) > 20) then
        begin
          FErrorCode := NH_ResError;
          FErrorDesc := 'Execute: ListUPS 20s timeout.';
          Exit;
        end;
      end;
      NH_Net_7ReqVar:
      begin
        if tickElapsedSec(tickStatus, tickNow) > 30 then
        begin
          doStatus('OK SendString LIST VAR ' + FUPS.DevId);
          FSocketHlp.SendString('LIST VAR ' + FUPS.DevId + LineEnding);
          tickStatus := tickNow;
          FnetStatus := NH_Net_8WaitVar;
        end;
      end;
      NH_Net_8WaitVar:
      begin
        if FSocketHlp.WaitigData > 0 then
        begin //some data
          br:= False;
          ss := FSocketHlp.ReceivePacket(2000);
          if (FUPStype = UPS_NUT) then
          begin
            br := FUPS.ProcessNUTvar(ss);
          end
          else if (FUPStype = UPS_PowerMaster) then
          begin
            br := FUPS.ProcessPMvar(ss);
          end;

          if (br) then
          begin
            doStatus('OK Receive VAR from ' + FUPS.DevId);
            tickStatus := tickNow;
            FnetStatus := NH_Net_7ReqVar;
          end
          else
          begin
            //received some garbage
            doStatus('ERR Receive unknown data.');
          end;

        end;

      end;
      NH_Net_9Idle:
      begin

      end;
    end;//end case
    Sleep(250);
  end;//end while not terminated


{
  r := netsock.Bind(FLocalIP, FLocalPort);
  if r <> True then
  begin
    FErrorCode := NH_ResError;
    FErrorDesc := 'Execute: TSocketHelper.Bind error.' + LineEnding +
      netsock.LastErrorDesc;
    netsock.Free;
    Exit;
  end;


  r := netsock.Connect(FRemoteIP, FRemotePort);
  if r <> True then
  begin
    FErrorCode := NH_ResError;
    FErrorDesc := 'Execute: TSocketHelper.Connect error.' + LineEnding +
      netsock.LastErrorDesc;
    netsock.Free;
    Exit;
  end;

  if FUPStype = UPS_NUT then
  begin
    r := True;
    if (FRemoteUser <> '') and (FRemotePass <> '') and (r) then
    begin
      r := loginNUT(netsock);
    end;

  end;


  if FAction = NH_ActionTestConn then
  begin
    resetError;
    netsock.Free;
    Exit;
  end;

  ups := TUPSdeviceHelper.Create;
  ups.DevId := FRemoteUPS;

  end;

  while (not Terminated) do
  begin

    //receive
    p := netsock.WaitigData;
    if p > 0 then
    begin
      s := netsock.ReceivePacket(2000);
      tickLastConn := tickNow;
      //process data
      if (FUPStype = UPS_NUT) then
      begin
        if (ups.DevId = '') and (Pos('BEGIN LIST UPS', s) > 0) then
        begin
          ups.ProcessNUTinit(s);
        end
        else if (Pos('BEGIN LIST VAR', s) > 0) then
        begin
          ups.ProcessNUTvar(s);
          ShowMessage('UPS status: ' + UPSstatusDesc(ups.Device.Status) +
            ' (' + ups.Device.StatusRaw + ')');
        end;
      end
      else if (FUPStype = UPS_PowerMaster) then
      begin
        ups.ProcessPMplus(s);
      end;



      if (FAction = NH_ActionListUPS) then
      begin //get first data and exit
        Clipboard.SetAsHtml(s, s);
        ups.Free;
        netsock.Free;
        Exit;
      end;

      if netsock.FErrorCode = NH_ResOK then
      begin
        //no error, some data, process them
        ShowMessage('data: ' + s);
      end
      else
      begin
        //something wrong, no data
        //log this error
      end;
    end
    else if (FAction = NH_ActionRun) then
    begin
      //check timeouts
      if (FUPStype = UPS_NUT) then
      begin  //last transmission timeout
        if (tickElapsedSec(tickLastConn, tickNow) > 300) then
        begin
          //reconnect
          try
            r := netsock.Bind(FLocalIP, FLocalPort);
            //log bind problem
            r := netsock.Connect(FRemoteIP, FRemotePort);
            //log connect error
            if r then
            begin
              tickLastConn := tickNow;
              tickLoop := 0;
              //log event reconnected
              if (FRemoteUser <> '') and (FRemotePass <> '') then
              begin
                if loginNUT(netsock) then
                begin
                  //login ok
                  //log this event

                end
                else
                begin
                  //login failed
                  //log this error
                end;
              end;
            end;

          except
            //log exception error
          end;
        end
        else if (tickElapsedSec(tickLastConn, tickNow) > 120) or
          (tickElapsedSec(tickLoop, tickNow) > 60) then
        begin //send var request
          tickLoop := tickNow;
          if (ups.DevId = '') then
          begin //send list ups to init
            netsock.SendString('LIST UPS' + LineEnding);
          end
          else
          begin
            netsock.SendString('LIST VAR ' + ups.DevId + LineEnding);
          end;
        end;
      end;
    end
    else if (FAction = NH_ActionListUPS) then
    begin
      if (tickElapsedSec(tickStart, tickNow) > 21) then
      begin
        //listups timeout
        ups.Free;
        netsock.Free;
        FErrorCode := NH_ResError;
        FErrorDesc := 'Execute: Action ListUPS 20s timeout.';
        Exit;
      end;

      if (FUPStype = UPS_NUT) then
      begin
        if (tickElapsedSec(tickLoop, tickNow) > 4) then
        begin
          //NUT list ups
          netsock.SendString('LIST UPS' + LineEnding);
          tickLoop := tickNow;
        end;
      end;
    end;

    //send


    Sleep(250);

  end; //loop end

  netsock.Free; }
end;

procedure TNetHelper.SetLocal(ip, port: string);
begin
  FLocalIP := ip;
  FLocalPort := port;
end;

procedure TNetHelper.SetRemote(ip, port: string);
begin
  FRemoteIP := ip;
  FRemotePort := port;
end;

procedure TNetHelper.SetCredentials(user, pass: string);
begin
  FRemoteUser := user;
  FRemotePass := pass;
end;

procedure TNetHelper.SetUPSdeviceid(id: string);
begin
  FUPS.DevId := id;

end;

procedure TNetHelper.setUPStype(AValue: TUPSNetServiceType);
begin
  FUPStype := AValue;
end;

procedure TNetHelper.resetError;
begin
  FErrorCode := NH_ResOK;
  FErrorDesc := '';
  FStatusDesc := '';
end;

procedure TNetHelper.doStatus(s: string);
begin
  FStatusDesc := s;
  Synchronize(@runStatus);
end;

procedure TNetHelper.runStatus;
begin
  frmWindow.statusText := FStatusDesc;
  frmWindow.ShowStatus;
end;

end.
