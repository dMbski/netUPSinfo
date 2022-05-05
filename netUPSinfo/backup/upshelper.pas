unit upshelper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, synautil;

const

  UPS_UnkValue = -1;     {unkown value const}
  UPS_PowerFactorDef = 0.75; {default powerfactor}

type

  TUPSbatterystatusType = (
    UPS_BattStatusUnk,    {Unknown status}
    UPS_BattStatusOk,     {normal work, nothing happening }
    UPS_BattDisChrg,      {battery discharging, ups working OB}
    UPS_BattCharging,     {battery charging, ups working OL after OB}
    UPS_BattNeedRepl      {old battery, needs replacement}
    );

  TUPSdevicestatusType = (
    UPS_StatusUnknown,   {unknown status}
    UPS_StatusOL,        {UPS online, normal work}
    UPS_StatusOB,        {UPS work on battery}
    UPS_StatusShutdown   {UPS shutdowns, check Timer}
    );

  TUPSbatteryType = record
    Charge: double;    {capacity (charge) left %}
    Replaced: string;   {battery replacement date}
    Runtime: double;            {Remaing runtime seconds sec}
    Status: TUPSbatterystatusType; {battery status}
    Voltage: double;            {current battery voltage V}
    VoltageNominal: double;     {nominal battery voltage ex. 12}
  end;

  TUPSinputType = record
    Frequency: double;  {input frequency Hz}
    Current: double;    {input current A}
    CurrentNominal: double; {current rating, max A}
    Load: double;       {input load on %}
    Voltage: double;    {input voltage V}
    VoltageNominal: double;   {nominal voltage V}
  end;

  TUPSoutputType = record
    Frequency: double;   {output frequency Hz}
    Current: double;     {output current A}
    CurrentNominal: double;  {output current rating, max A}
    Load: double;        {output load on %}
    Power: double;       {output power W}
    PowerNominal: double;    {output power rating, max W}
    Voltage: double;     {output voltage V}
    VoltageNominal: double;      {output nominal voltage V}
    PowerFactor: double;         {output powerfactor 0-1.0, def. 0.75}
  end;

  TUPSdeviceType = record
    Id: string;          {device identifier (suid or ups.id)}
    Model: string;       {model name}
    Firmware: string;    {firmware version}
    Serial: string;      {serial number}
    MFR: string;         {device manufacturer}
    Temperature: double; {device temperature}
    Timer: integer;      {time to shutdown ups (reboot, shutdown) sec}
    StatusRaw: string;      {device status in raw form from received data}
    Status: TUPSdevicestatusType;   {device status}
  end;

  { TUPSdeviceHelper }
  TUPSdeviceHelper = class(TObject)
  private
    Fbattery: TUPSbatteryType;
    Finput: TUPSinputType;
    Foutput: TUPSoutputType;
    Fdevice: TUPSdeviceType;
    Fid: string;
    Fdesc: string;
    Ferrordesc: string;
    Flastdata: TDateTime;

    procedure clearBattery;
    procedure clearDevice;
    procedure clearInput;
    procedure clearOutput;
  public
    constructor Create;
    destructor Destroy; override;

    function ProcessNUTvar(var rawdata: string): boolean;
    function ProcessNUTinit(var rawdata: string): boolean;
    function ProcessPMvar(var rawdata: string): boolean;
    function ProcessPMinit(var rawdata: string): boolean;
    function StatusRaw: string;

    property LastData: TDateTime read Flastdata;
    property LastErrorDesc: string read Ferrordesc;
    property DevId: string read FId write Fid;
    property DevDesc: string read Fdesc write Fdesc;
    property Device: TUPSdeviceType read FDevice;
    property Battery: TUPSbatteryType read FBattery;
    property Input: TUPSinputType read FInput;
    property Output: TUPSoutputType read FOutput;
  end;

{returns description for TUPSdevicestatusType}
function UPSstatusDesc(stat: TUPSdevicestatusType): string;
{returns unquoted value of given parameter name from NUT var list}
function GetNUTValue(rawdata, paramname: string): string;

implementation

function UPSstatusDesc(stat: TUPSdevicestatusType): string;
begin
  Result := 'Unknown';
  case stat of
    UPS_StatusOL:
      Result := 'UPS on line';
    UPS_StatusOB:
      Result := 'UPS on battery';
    UPS_StatusShutdown:
      Result := 'UPS shutdowns';
  end;
end;

function GetNUTValue(rawdata, paramname: string): string;
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
  Result := GetBetween('"', '"', s);

end;


{ TUPSdeviceHelper }

procedure TUPSdeviceHelper.clearBattery;
begin
  FBattery.Charge := UPS_UnkValue;
  FBattery.Replaced := '';
  FBattery.Runtime := UPS_UnkValue;
  FBattery.Status := UPS_BattStatusUnk;
  FBattery.Voltage := UPS_UnkValue;
  FBattery.VoltageNominal := UPS_UnkValue;
end;

procedure TUPSdeviceHelper.clearDevice;
begin
  FDevice.Status := UPS_StatusUnknown;
  FDevice.Temperature := UPS_UnkValue;
  FDevice.Timer := UPS_UnkValue;
  FDevice.Id := Fid;
  FDevice.Firmware := '';
  FDevice.MFR := '';
  FDevice.Model := '';
  FDevice.Serial := '';
  FDevice.StatusRaw := '';
end;

procedure TUPSdeviceHelper.clearInput;
begin
  FInput.Voltage := UPS_UnkValue;
  FInput.VoltageNominal := UPS_UnkValue;
  FInput.Current := UPS_UnkValue;
  FInput.CurrentNominal := UPS_UnkValue;
  FInput.Frequency := UPS_UnkValue;
  Finput.Load := UPS_UnkValue;

end;

procedure TUPSdeviceHelper.clearOutput;
begin
  FOutput.Frequency := UPS_UnkValue;
  FOutput.CurrentNominal := UPS_UnkValue;
  FOutput.Current := UPS_UnkValue;
  FOutput.Voltage := UPS_UnkValue;
  FOutput.VoltageNominal := UPS_UnkValue;
  FOutput.Load := UPS_UnkValue;
  FOutput.Power := UPS_UnkValue;
  FOutput.PowerNominal := UPS_UnkValue;
  FOutput.PowerFactor := UPS_PowerFactorDef;
end;

constructor TUPSdeviceHelper.Create;
begin
  Ferrordesc := '';
  Flastdata := UPS_UnkValue;
  clearBattery;
  clearDevice;
  clearInput;
  clearOutput;
end;

destructor TUPSdeviceHelper.Destroy;
begin
  Ferrordesc := '';
  clearBattery;
  clearDevice;
  clearInput;
  clearOutput;
end;

function TUPSdeviceHelper.ProcessNUTvar(var rawdata: string): boolean;
var
  r: string;
  d: double;
  i: integer;
  ods: char;

  function getNutVarDbl(pn: string): double;
  begin
    Result := StrToFloatDef(GetNUTValue(rawdata, pn), UPS_UnkValue);
  end;

  function getNutVarInt(pn: string): integer;
  begin
    Result := StrToIntDef(GetNUTValue(rawdata, pn), UPS_UnkValue);
  end;

begin
  Result := False;
  Ferrordesc := '';
  if not (Pos('BEGIN LIST VAR', rawdata) > 0) then
  begin
    Ferrordesc := 'Not NUT variables list.';
    Exit;
  end;

  ods := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := '.';

  //device  + battery status
  clearDevice;
  clearBattery;

  Flastdata := Now;

  r := GetNUTValue(rawdata, 'ups.status');
  FDevice.StatusRaw := r;
  if r <> '' then
  begin
    if Pos('OL', r) > 0 then
    begin
      Fdevice.Status := UPS_StatusOL;
      if Pos('CHRG', r) > 0 then
      begin
        Fbattery.Status := UPS_BattCharging;
      end
      else
        Fbattery.Status := UPS_BattStatusOk;
    end
    else if Pos('OB', r) > 0 then
    begin
      Fdevice.Status := UPS_StatusOB;
      Fbattery.Status := UPS_BattDisChrg;
    end;
  end;

  FDevice.Id := Fid;
  FDevice.Temperature := getNutVarDbl('ups.temperature');
  FDevice.Firmware := GetNUTValue(rawdata, 'ups.firmware');
  FDevice.MFR := GetNUTValue(rawdata, 'ups.mfr');
  FDevice.Model := GetNUTValue(rawdata, 'ups.model');
  FDevice.Serial := GetNUTValue(rawdata, 'ups.serial');

  i := getNutVarInt('ups.timer.reboot');
  if i > 0 then
    FDevice.Timer := i;

  i := getNutVarInt('ups.timer.shutdown');
  if (i > 0) and (i < FDevice.Timer) then

    FDevice.Timer := i;

  if FDevice.Timer > 0 then
  begin
    Fdevice.Status := UPS_StatusShutdown;
  end;

  //battery
  r := GetNUTValue(rawdata, 'battery.date');
  if (r = '') or (UpperCase(r) = 'NOT SET') then
    r := GetNUTValue(rawdata, 'battery.mfr.date');
  FBattery.Replaced := r;

  FBattery.Charge := getNutVarDbl('battery.charge');
  FBattery.Runtime := getNutVarDbl('battery.runtime');
  FBattery.Voltage := getNutVarDbl('battery.voltage');
  FBattery.VoltageNominal := getNutVarDbl('battery.voltage.nominal');
  //input
  clearInput;
  FInput.Voltage := getNutVarDbl('input.voltage');
  FInput.VoltageNominal := getNutVarDbl('input.voltage.nominal');
  FInput.Current := getNutVarDbl('input.current');
  FInput.CurrentNominal := getNutVarDbl('input.current.nominal');
  FInput.Frequency := getNutVarDbl('input.frequency');
  Finput.Load := getNutVarDbl('input.load');
  //Output
  clearOutput;

  FOutput.Frequency := getNutVarDbl('output.frequency');
  FOutput.CurrentNominal := getNutVarDbl('output.current.nominal');
  FOutput.Current := getNutVarDbl('output.current');
  FOutput.Voltage := getNutVarDbl('output.voltage');
  FOutput.VoltageNominal := getNutVarDbl('output.voltage.nominal');
  FOutput.Load := getNutVarDbl('ups.load');
  Foutput.PowerFactor := getNutVarDbl('powerfactor');
  if (Foutput.PowerFactor = UPS_UnkValue) then
    Foutput.PowerFactor := UPS_PowerFactorDef; //check pf, to default

  //get V to recalculate power
  d := FOutput.Voltage;
  if d = UPS_UnkValue then
    d := Finput.Voltage;

  if d = UPS_UnkValue then
    d := FOutput.VoltageNominal;

  if d = UPS_UnkValue then
    d := FInput.VoltageNominal;
  //try receive some values
  FOutput.Power := getNutVarDbl('realpower');
  if FOutput.Power = UPS_UnkValue then
    FOutput.Power := getNutVarDbl('power');

  //nut gives current, recalculate with V
  if (FOutput.Power = UPS_UnkValue) and (d <> UPS_UnkValue) then
  begin
    FOutput.Power := getNutVarDbl('output.current');
    if FOutput.Power <> UPS_UnkValue then
      FOutput.Power := d * FOutput.Power * Foutput.PowerFactor; // PF
    FOutput.PowerNominal := getNutVarDbl('output.current.nominal');
    if FOutput.PowerNominal <> UPS_UnkValue then
      FOutput.PowerNominal := d * Output.PowerNominal * Foutput.PowerFactor; //PF
  end;
  //recalculate load
  if (FOutput.Load = UPS_UnkValue) then
  begin
    if (FOutput.PowerNominal > 0) and (FOutput.Power <> UPS_UnkValue) then
      FOutput.Load := (FOutput.Power / FOutput.PowerNominal) * 100;
  end;

  FormatSettings.DecimalSeparator := ods;
  Result := True;
end;

function TUPSdeviceHelper.ProcessNUTinit(var rawdata: string): boolean;
var
  p: integer;
  s: string;
begin
  Result := False;
  Ferrordesc := '';
  if not (Pos('BEGIN LIST UPS', rawdata) > 0) then
  begin
    Ferrordesc := 'Not NUT ups list.';
    Exit;
  end;

  s := Trim(GetBetween('BEGIN LIST UPS', 'END LIST ', rawdata));
  p := Pos('UPS ', s);
  if p > 0 then
  begin
    s := Trim(s.Substring(p + 3)); //-1 + lenght 'UPS '
    p := Pos(' ', s);
    if p > 0 then
      Fid := s.Substring(0, p);
    Fdesc := GetBetween('"', '"', s.Substring(p));
  end
  else
  begin
    Ferrordesc := 'No ups name data: ' + s;
    Exit;
  end;

  Result := True;

end;

function TUPSdeviceHelper.ProcessPMvar(var rawdata: string): boolean;
begin
  //placeholder
  Result := False;
end;

function TUPSdeviceHelper.ProcessPMinit(var rawdata: string): boolean;
begin
  //placeholder
  Result := False;
end;

function TUPSdeviceHelper.StatusRaw: string;
begin
  Result := Fdevice.StatusRaw;
end;

end.
