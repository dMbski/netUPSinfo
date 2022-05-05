unit mainfrm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, Menus,
  ComCtrls, Buttons, StdCtrls, IniFiles, synaIP,
  blcksock, upsinfo_nut, upsinfo_def;

type

  { TfrmWindow }

  TfrmWindow = class(TForm)
    bb1Cancel: TBitBtn;
    bb2Ok: TBitBtn;
    Button1: TButton;
    cbUpsType: TComboBox;
    edLocIP: TComboBox;
    edUpsID: TEdit;
    edUser: TEdit;
    edPass: TEdit;
    edRemPort: TEdit;
    edRemIP: TEdit;
    edLocPort: TEdit;
    frmTray: TTrayIcon;
    frmMenu: TMainMenu;
    gbDevice: TGroupBox;
    gbOutput: TGroupBox;
    gbBatt: TGroupBox;
    gbUpsCfg: TGroupBox;
    gbInput: TGroupBox;
    labDevice: TStaticText;
    labDevice1: TStaticText;
    labInput1: TStaticText;
    labInput2: TStaticText;
    labOutput: TStaticText;
    labOutput1: TStaticText;
    labOutput2: TStaticText;
    labBattery: TStaticText;
    labBattery1: TStaticText;
    labBattery2: TStaticText;
    labUpsID: TLabel;
    labUser: TLabel;
    labPass: TLabel;
    labLocIP: TLabel;
    labRemPort: TLabel;
    labRemIP: TLabel;
    labLocPort: TLabel;
    Memo1: TMemo;
    MenuItem1: TMenuItem;
    miGraph: TMenuItem;
    miLog: TMenuItem;
    miView: TMenuItem;
    miFileExit: TMenuItem;
    miFileConfig: TMenuItem;
    miFile: TMenuItem;
    frmPages: TPageControl;
    labInput: TStaticText;
    Tab1Run: TTabSheet;
    Tab2Config: TTabSheet;
    Tab0Run: TTabSheet;
    procedure bb1CancelClick(Sender: TObject);
    procedure bb2OkClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure edLocIPExit(Sender: TObject);
    procedure cbUpsTypeChange(Sender: TObject);
    procedure edRemIPExit(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormWindowStateChange(Sender: TObject);
    procedure frmTrayDblClick(Sender: TObject);
    procedure miFileConfigClick(Sender: TObject);
    procedure miFileExitClick(Sender: TObject);
    procedure miGraphClick(Sender: TObject);
    procedure miLogClick(Sender: TObject);
    procedure Tab1RunResize(Sender: TObject);
  private
    iniConfig: TIniFile;
    logLevel: integer;

    function iniRS(section: string; ident: string; def: string = ''): string;
    procedure logMe(msg: string; lvl: integer = 0);
    procedure LoadConfig;
    procedure PrepConfig;
    procedure RunConfig;
    procedure FormToTaskbar;
  public
    statusText: string;
    statDevice: TUPSdeviceType;
    statBattery: TUPSbatteryType;
    statInput: TUPSinputType;
    statOutput: TUPSoutputType;
    procedure ShowStatus;
    procedure ShowData;
  end;

var
  frmWindow: TfrmWindow;
  netupsNUT: TUPSinfoNUTthread;


const
  logLevInfo = 0;
  logLevWarn = 1;
  logLevComm = 2;
  logLevError = 3;

  logDesc0 = 'Info';
  logDesc1 = 'Warn';
  logDesc2 = 'Comm';
  logDesc3 = 'Error';

  formatDefDecSep = '.';
  formatDefDate = 'yyyy-MM-dd';
  formatDefTime = 'hh:nn:ss';

  upsSrvDesc0 = 'Not configured';
  upsSrvDesc1 = 'PowerMaster+';
  upsSrvDesc2 = 'Network UPS Tools (NUT)';

implementation

{$R *.lfm}

{ TfrmWindow }

procedure TfrmWindow.FormCreate(Sender: TObject);
var
  sfn: string;
begin
  logLevel := logLevInfo;
  //clear
  Memo1.Clear;
  cbUpsType.Clear;

  gbInput.Caption := '';
  gbOutput.Caption := '';
  gbBatt.Caption := '';
  gbDevice.Caption := '';

  //labels
  labInput.Caption := 'Input:';
  labOutput.Caption := 'Output:';
  labBattery.Caption := 'Battery:';
  labDevice.Caption := 'Device:';

  labInput1.Caption := '';
  labInput2.Caption := 'no data';
  labOutput1.Caption := '';
  labOutput2.Caption := 'no data';
  labBattery1.Caption := '';
  labBattery2.Caption := 'no data';
  labDevice1.Caption := 'no data';

  //config
  sfn := ChangeFileExt(Application.ExeName, '.config');
  if (not FileExists(sfn)) then
  begin
    logMe('No config file: ' + sfn, logLevWarn);
  end;



  iniConfig := TIniFile.Create(sfn);
  PrepConfig;
  //create main window

  frmPages.ShowTabs := False;
  frmPages.ActivePageIndex := Tab0Run.TabIndex;

  //config trayicon
  frmTray.Icon := Application.Icon;
  frmTray.Hide;
  frmTray.Hint := frmWindow.Caption;


  //netupsNUT := nil;
  //run thread
  netupsNUT := TUPSinfoNUTthread.Create;
  LoadConfig;
  RunConfig;

  netupsNUT.Start;
end;

procedure TfrmWindow.bb1CancelClick(Sender: TObject);
begin
  frmPages.ActivePageIndex := Tab1Run.TabIndex;
  LoadConfig;
end;

procedure TfrmWindow.bb2OkClick(Sender: TObject);
begin
  { TODO : Save param to ini and reinit app }

  iniConfig.WriteInteger('ups0', 'type', cbUpsType.ItemIndex);
  iniConfig.WriteString('ups0', 'localIP', edLocIP.Text);
  iniConfig.WriteString('ups0', 'localPort', edLocPort.Text);
  iniConfig.WriteString('ups0', 'upsId', edUpsID.Text);
  iniConfig.WriteString('ups0', 'remoteIP', edRemIP.Text);
  iniConfig.WriteString('ups0', 'remotePort', edRemPort.Text);
  iniConfig.WriteString('ups0', 'user', edUser.Text);
  iniConfig.WriteString('ups0', 'pass', edPass.Text);

  PrepConfig;
  LoadConfig;

  MessageDlg('Config', 'Parameters written to config file', mtInformation, [mbOK], 0);
  frmPages.ActivePageIndex := Tab1Run.TabIndex;
  //run thread
  if netupsNUT <> nil then
  begin
    netupsNUT.Terminate;
    netupsNUT.WaitFor;
    netupsNUT := nil;
  end;

  netupsNUT := TUPSinfoNUTthread.Create;
  RunConfig;
  netupsNUT.Start;

end;

procedure TfrmWindow.Button1Click(Sender: TObject);
begin

  if netupsNUT <> nil then
  begin
    netupsNUT.Terminate;
    netupsNUT.WaitFor;
    netupsNUT := nil;
  end;

  netupsNUT := TUPSinfoNUTthread.Create;
  RunConfig;
  netupsNUT.Start;

end;

procedure TfrmWindow.edLocIPExit(Sender: TObject);
begin
  if not isIP(edLocIP.Text) then
    MessageDlg('Not valid entry', 'Enter the correct IPv4 address (a.b.c.d).',
      mtWarning, [mbClose], 0);
end;

procedure TfrmWindow.cbUpsTypeChange(Sender: TObject);
begin
  case TUPSNetServiceType(cbUpsType.ItemIndex) of
    UPS_Any:
    begin
      edLocPort.Text := '0';
      edRemPort.Text := '0';
      edRemPort.Color := clDefault;
      edUser.Color := clDefault;
      edPass.Color := clDefault;
    end;
    UPS_PowerMaster:
    begin
      edLocPort.Text := '3052';
      edRemPort.Text := '0';
      edRemPort.Color := clSilver;
      edUser.Color := clSilver;
      edPass.Color := clSilver;
    end;
    UPS_NUT:
    begin
      edLocPort.Text := '0';
      edRemPort.Text := '3493';
      edRemPort.Color := clDefault;
      edUser.Color := clDefault;
      edPass.Color := clDefault;
    end;
  end;

end;

procedure TfrmWindow.edRemIPExit(Sender: TObject);
begin
  if not isIP(edRemIP.Text) then
    MessageDlg('Not valid entry', 'Enter the correct IPv4 address (a.b.c.d).',
      mtWarning, [mbClose], 0);
end;

procedure TfrmWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if MessageDlg('Close application???', 'Chose Yes to close application' +
    LineEnding + 'Chose No to minimize window', mtConfirmation, [mbYes, mbNo], 0) =
    mrYes then
  begin
    CloseAction := caFree;
  end
  else
  begin
    CloseAction := caNone;
    WindowState := wsMinimized;
    FormToTaskbar;
  end;

end;

procedure TfrmWindow.FormDestroy(Sender: TObject);
begin
  //close app
  iniConfig.Free;
  if netupsNUT <> nil then
  begin
    netupsNUT.Terminate;
    netupsNUT.WaitFor;
  end;

  logMe('FormDestroy.', logLevInfo);
end;

procedure TfrmWindow.FormWindowStateChange(Sender: TObject);
begin
  if frmWindow.WindowState = wsMinimized then
  begin
    FormToTaskbar;
  end;
end;

procedure TfrmWindow.frmTrayDblClick(Sender: TObject);
begin
  frmWindow.WindowState := wsNormal;
  frmWindow.Show;
  frmWindow.SetFocus;
  frmTray.Hide;
end;

procedure TfrmWindow.miFileConfigClick(Sender: TObject);
begin
  //prepare window
  PrepConfig;

  LoadConfig;
  //switch to
  frmPages.ActivePageIndex := Tab2Config.TabIndex;
end;

procedure TfrmWindow.miFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmWindow.miGraphClick(Sender: TObject);
begin
  if frmPages.ActivePageIndex = Tab2Config.TabIndex then
    Exit;
  frmPages.ActivePageIndex := Tab0Run.TabIndex;
end;

procedure TfrmWindow.miLogClick(Sender: TObject);
begin
  if frmPages.ActivePageIndex = Tab2Config.TabIndex then
    Exit;
  frmPages.ActivePageIndex := Tab1Run.TabIndex;
end;

procedure TfrmWindow.Tab1RunResize(Sender: TObject);
begin
  Memo1.Top := 40;
  Memo1.Height := Tab1Run.Height - Memo1.Top;
end;

function TfrmWindow.iniRS(section: string; ident: string; def: string): string;
begin
  if (section = '') or (ident = '') then
  begin
    logMe('ini readString with empty parameters, section: ' + section +
      ' ident: ' + ident, logLevError);
    Result := def;
    Exit;
  end;

  Result := StringReplace(iniConfig.ReadString(section, ident, def),
    '"', '', [rfReplaceAll]);
end;

procedure TfrmWindow.logMe(msg: string; lvl: integer);
var
  s: string;
  lvldesc: array[0..3] of string = (logDesc0, logDesc1, logDesc2, logDesc3);
begin
  if lvl < logLevel then
    Exit;

  s := '[' + DateTimeToStr(Now) + '][' + lvldesc[lvl] + ']'#9 + msg;
  { TODO : proper log to file }
  Memo1.Append(s);

end;

procedure TfrmWindow.LoadConfig;
var
  n: integer;
begin
  if iniConfig = nil then
  begin
    logMe('iniConfig=nil', logLevError);
  end;

  if (not iniConfig.SectionExists('config')) then
  begin
    logMe('iniConfig, no section [config]', logLevWarn);
  end;

  logLevel := iniConfig.ReadInteger('config', 'LogLevel', logLevInfo);

  FormatSettings.DecimalSeparator :=
    iniRS('config', 'formatDecimalSep', formatDefDecSep).Chars[0];


  FormatSettings.ShortDateFormat :=
    iniRS('config', 'formatDate', formatDefDate);

  FormatSettings.LongTimeFormat := iniRS('config', 'formatTime', formatDefTime);

  logMe('Format settings, Decimal Sep: ' + FormatSettings.DecimalSeparator +
    ' Date: ' + FormatSettings.ShortDateFormat + ' Time: ' +
    FormatSettings.LongTimeFormat);

  if (not iniConfig.SectionExists('ups0')) then
  begin
    logMe('iniConfig, no section [ups0]', logLevError);
    Exit;
  end;

  n := iniConfig.ReadInteger('ups0', 'type', 0);
  if (n < cbUpsType.Items.Count) then
    cbUpsType.ItemIndex := n;
  edLocIP.Text := iniRS('ups0', 'localIP');
  edLocPort.Text := iniRS('ups0', 'localPort');
  edUpsID.Text := iniRS('ups0', 'upsId');
  edRemIP.Text := iniRS('ups0', 'remoteIP');
  edRemPort.Text := iniRS('ups0', 'remotePort');
  edUser.Text := iniRS('ups0', 'user');
  edPass.Text := iniRS('ups0', 'pass');

end;

procedure TfrmWindow.PrepConfig;
var
  ts: TUDPBlockSocket;
begin
  //prepare controls and edits
  gbUpsCfg.Caption := 'Network UPS service type and configuration: ';
  cbUpsType.Clear;
  cbUpsType.Items.Add(upsSrvDesc0);
  cbUpsType.Items.Add(upsSrvDesc1);
  cbUpsType.Items.Add(upsSrvDesc2);
  cbUpsType.ItemIndex := 0;

  edLocIP.Clear;
  try
    ts := TUDPBlockSocket.Create;
    ts.PreferIP4 := True;
    ts.Family := SF_IP4;        //need only v4
    ts.ResolveNameToIP(ts.LocalName, edLocIP.Items);
  finally
    ts.Free;
  end;
  edLocPort.Text := '0';

  edRemIP.Text := '';
  edRemPort.Text := '0';
  edUser.Text := '';
  edPass.Text := '';

  edUpsID.Text := '';

end;

procedure TfrmWindow.RunConfig;
begin
  if netupsNUT = nil then
    Exit;

  netupsNUT.SetLocal(edLocIP.Text, edLocPort.Text);
  netupsNUT.SetRemote(edRemIP.Text, edRemPort.Text);
  netupsNUT.SetCredentials(edUser.Text, edPass.Text);
  netupsNUT.SetDeviceId(edUpsID.Text);

end;

procedure TfrmWindow.FormToTaskbar;
begin
  frmWindow.Hide;
  frmTray.Show;
end;

procedure TfrmWindow.ShowStatus;
begin
  if statusText = '' then
    Exit;
  //ShowMessage('Status: ' + statusText);
  logMe('Status: ' + statusText);
  statusText := '';
end;

procedure TfrmWindow.ShowData;
var
  scap, sval: string;
begin
  //input
  {Memo1.Append('Input: Volt: ' + FloatToStr(statInput.Voltage) +
    ' (' + FloatToStr(statInput.VoltageNominal) + '), Curr: ' +
    FloatToStr(statInput.Current) + ' (' + FloatToStr(statInput.CurrentNominal) +
    '), Load: ' + FloatToStr(statInput.Load) + ', Freq: ' +
    FloatToStr(statInput.Frequency)); }

  scap := 'Voltage (Vnom.):';
  sval := FloatToStr(statInput.Voltage) + ' (' +
    FloatToStr(statInput.VoltageNominal) + ')';
  scap := scap + LineEnding + 'Current (Inom.):';
  sval := sval + LineEnding + FloatToStr(statInput.Current) + ' (' +
    FloatToStr(statInput.CurrentNominal) + ')';
  scap := scap + LineEnding + 'Frequency:';
  sval := sval + LineEnding + FloatToStr(statInput.Frequency);
  scap := scap + LineEnding + 'Load:';
  sval := sval + LineEnding + FloatToStr(statInput.Load);
  labInput1.Caption := scap;
  labInput2.Caption := sval.Replace('-1', ' ');

  //output
  {Memo1.Append('Output: Volt: ' + FloatToStr(statOutput.Voltage) +
    ' (' + FloatToStr(statOutput.VoltageNominal) + '), Curr: ' +
    FloatToStr(statOutput.Current) + ' (' + FloatToStr(statOutput.CurrentNominal) +
    '), Load: ' + FloatToStr(statOutput.Load) + ', Freq: ' +
    FloatToStr(statOutput.Frequency) + ', Power: ' + FloatToStr(statOutput.Power) +
    ' (' + FloatToStr(statOutput.PowerNominal) + ')'); }

  scap := 'Voltage (Vnom.):';
  sval := FloatToStr(statOutput.Voltage) + ' (' +
    FloatToStr(statOutput.VoltageNominal) + ')';
  scap := scap + LineEnding + 'Current (Inom.):';
  sval := sval + LineEnding + FloatToStr(statOutput.Current) + ' (' +
    FloatToStr(statOutput.CurrentNominal) + ')';
  scap := scap + LineEnding + 'Frequency:';
  sval := sval + LineEnding + FloatToStr(statOutput.Frequency);
  scap := scap + LineEnding + 'Load:';
  sval := sval + LineEnding + FloatToStr(statOutput.Load);
  scap := scap + LineEnding + 'Power (Pnom.):';
  sval := sval + LineEnding + FloatToStr(statOutput.Power) + ' (' +
    FloatToStr(statOutput.PowerNominal) + ')';
  labOutput1.Caption := scap;
  labOutput2.Caption := sval.Replace('-1', ' ');

  //battery
  {Memo1.Append('Battery: Volt: ' + FloatToStr(statBattery.Voltage) +
    ' (' + FloatToStr(statBattery.VoltageNominal) + '), Charge: ' +
    FloatToStr(statBattery.Charge) + ', Status: ' +
    GetStatDescBatt(statBattery.Status) + ', Runtime: ' +
    FloatToStr(statBattery.Runtime) + ', Replaced: ' + statBattery.Replaced); }

  scap := 'Voltage (Vnom.):';
  sval := FloatToStr(statBattery.Voltage) + ' (' +
    FloatToStr(statBattery.VoltageNominal) + ')';
  scap := scap + LineEnding + 'Charge (%):';
  sval := sval + LineEnding + FloatToStr(statBattery.Charge);
  scap := scap + LineEnding + 'Status:';
  sval := sval + LineEnding + GetStatDescBatt(statBattery.Status);
  scap := scap + LineEnding + 'Runtime (sec.):';
  sval := sval + LineEnding + FloatToStr(statBattery.Runtime);
  scap := scap + LineEnding + 'Replaced:';
  sval := sval + LineEnding + statBattery.Replaced;
  labBattery1.Caption := scap;
  labBattery2.Caption := sval.Replace('-1', ' ');

  //device
  Memo1.Append('Device: ' + statDevice.MFR + ' ' + statDevice.Model +
    ' (' + statDevice.Firmware + '), SN: ' + statDevice.Serial +
    ', id: ' + statDevice.Id + ' (' + statDevice.Desc + '), status: ' +
    GetStatDescDevice(statDevice.Status));
  scap := statDevice.Id + ' (' + statDevice.Desc + ')';
  scap := scap + LineEnding + statDevice.MFR + ' ' + statDevice.Model;
  scap := scap + LineEnding + 'SN: ' + statDevice.Serial;
  scap := scap + LineEnding + 'Firmware: ' + statDevice.Firmware;
  scap := scap + LineEnding + 'Temperature: ' + FloatToStr(statDevice.Temperature);
  scap := scap + LineEnding + 'Status: ' + GetStatDescDevice(statDevice.Status);
  labDevice1.Caption := scap;

end;


end.
