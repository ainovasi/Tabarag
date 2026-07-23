unit uServiceManagerForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  AsyncProcess, Process;

type

  { TServiceManagerForm }

  TServiceManagerForm = class(TForm)
    btnStartEmbed: TButton;
    btnStopEmbed: TButton;
    btnStartLLM: TButton;
    btnStopLLM: TButton;
    memLogEmbed: TMemo;
    memLogLLM: TMemo;
    pnlControls: TPanel;
    pnlEmbedHeader: TPanel;
    pnlLLMHeader: TPanel;
    pnlEmbedLeft: TPanel;
    pnlLLMRight: TPanel;
    splitterMain: TSplitter;
    procedure btnStartEmbedClick(Sender: TObject);
    procedure btnStartLLMClick(Sender: TObject);
    procedure btnStopEmbedClick(Sender: TObject);
    procedure btnStopLLMClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FProcEmbed: TAsyncProcess;
    FProcLLM: TAsyncProcess;

    procedure OnProcessReadData(Sender: TObject);
    procedure OnProcessTerminate(Sender: TObject);
    procedure UpdateUIState;
    procedure SetupTerminalStyle(AMemo: TMemo);
  public
  end;

var
  ServiceManagerForm: TServiceManagerForm;

implementation

{$R *.lfm}

{ TServiceManagerForm }

procedure TServiceManagerForm.FormCreate(Sender: TObject);
begin
  // 1. Inisialisasi Proses Asinkron untuk Server Embedding (BGE-M3)
  FProcEmbed := TAsyncProcess.Create(nil);
  FProcEmbed.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcEmbed.OnReadData := @OnProcessReadData;
  FProcEmbed.OnTerminate := @OnProcessTerminate;

  // 2. Inisialisasi Proses Asinkron untuk Server LLM Chat (Gemma 3)
  FProcLLM := TAsyncProcess.Create(nil);
  FProcLLM.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcLLM.OnReadData := @OnProcessReadData;
  FProcLLM.OnTerminate := @OnProcessTerminate;

  // 3. Atur gaya kosmetik Memo agar mirip PowerShell/Terminal gelap
  SetupTerminalStyle(memLogEmbed);
  SetupTerminalStyle(memLogLLM);

  UpdateUIState;
end;

procedure TServiceManagerForm.FormDestroy(Sender: TObject);
begin
  // Pengamanan: Jika aplikasi ditutup, matikan service agar tidak menjadi zombie process
  if FProcEmbed.Running then FProcEmbed.Terminate(0);
  if FProcLLM.Running then FProcLLM.Terminate(0);

  FProcEmbed.Free;
  FProcLLM.Free;
end;

procedure TServiceManagerForm.FormShow(Sender: TObject);
begin

end;

procedure TServiceManagerForm.SetupTerminalStyle(AMemo: TMemo);
begin
  AMemo.Color := TColor($1C140C); // Biru Gelap/Hitam khas konsol
  AMemo.Font.Name := 'Consolas';
  AMemo.Font.Size := 10;
  AMemo.Font.Color := clGrayText;
  AMemo.ScrollBars := ssAutoBoth;
  AMemo.ReadOnly := True;
end;

procedure TServiceManagerForm.UpdateUIState;
begin
  // Mengatur interaksi tombol berdasarkan status aktif/tidaknya proses
  btnStartEmbed.Enabled := not FProcEmbed.Running;
  btnStopEmbed.Enabled := FProcEmbed.Running;

  btnStartLLM.Enabled := not FProcLLM.Running;
  btnStopLLM.Enabled := FProcLLM.Running;
end;

procedure TServiceManagerForm.btnStartEmbedClick(Sender: TObject);
var
  BaseDir: String;
begin
  BaseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + 'ai/');

  memLogEmbed.Clear;
  memLogEmbed.Lines.Add('>> Memulai Llama Server Embedding (Port 8081)...');

  // Konfigurasi Executable dan Argumen Komando
  FProcEmbed.Executable := BaseDir + 'llama-server.exe';
  FProcEmbed.Parameters.Clear;
  FProcEmbed.Parameters.Add('-m');
  FProcEmbed.Parameters.Add(ExpandFileName(BaseDir  + PathDelim + 'model' + PathDelim + 'bgem3.gguf'));
  FProcEmbed.Parameters.Add('--embedding');
  FProcEmbed.Parameters.Add('-c');
  FProcEmbed.Parameters.Add('8192');
  FProcEmbed.Parameters.Add('--port');
  FProcEmbed.Parameters.Add('8081');
  FProcEmbed.Parameters.Add('-t');
  FProcEmbed.Parameters.Add('4');

  try
    FProcEmbed.Execute;
    UpdateUIState;
  except
    on E: Exception do
      memLogEmbed.Lines.Add('ERROR gagal menjalankan executable: ' + E.Message);
  end;
end;

procedure TServiceManagerForm.btnStartLLMClick(Sender: TObject);
var
  BaseDir: String;
begin
  BaseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) +'ai/');

  memLogLLM.Clear;
  memLogLLM.Lines.Add('>> Memulai Llama Server Gemma 3 (Port 8080)...');

  FProcLLM.Executable := BaseDir + 'llama-server.exe';
  FProcLLM.Parameters.Clear;
  FProcLLM.Parameters.Add('-m');
  FProcLLM.Parameters.Add(ExpandFileName(BaseDir  + PathDelim + 'model' + PathDelim + 'gemma.gguf'));
  FProcLLM.Parameters.Add('--port');
  FProcLLM.Parameters.Add('8080');
  FProcLLM.Parameters.Add('-c');
  FProcLLM.Parameters.Add('4096');
  FProcLLM.Parameters.Add('-t');
  FProcLLM.Parameters.Add('6');

  try
    FProcLLM.Execute;
    UpdateUIState;
  except
    on E: Exception do
      memLogLLM.Lines.Add('ERROR gagal menjalankan executable: ' + E.Message);
  end;
end;

procedure TServiceManagerForm.btnStopEmbedClick(Sender: TObject);
begin
  if FProcEmbed.Running then
  begin
    FProcEmbed.Terminate(0);
    memLogEmbed.Lines.Add(LineEnding + '>> Service Embedding dihentikan oleh pengguna.');
  end;
end;

procedure TServiceManagerForm.btnStopLLMClick(Sender: TObject);
begin
  if FProcLLM.Running then
  begin
    FProcLLM.Terminate(0);
    memLogLLM.Lines.Add(LineEnding + '>> Service Gemma 3 dihentikan oleh pengguna.');
  end;
end;

{ Event ini dipicu secara otomatis oleh LCL saat server menulis log ke konsol }
procedure TServiceManagerForm.OnProcessReadData(Sender: TObject);
var
  CurrentProc: TAsyncProcess;
  TargetMemo: TMemo;
  AvailableBytes: Integer;
  BufferString: String;
begin
  CurrentProc := TAsyncProcess(Sender);

  // Arahkan output ke komponen Memo yang tepat
  if CurrentProc = FProcEmbed then
    TargetMemo := memLogEmbed
  else
    TargetMemo := memLogLLM;

  AvailableBytes := CurrentProc.Output.NumBytesAvailable;
  if AvailableBytes > 0 then
  begin
    // Alokasikan memori buffer string sesuai jumlah data yang masuk
    SetLength(BufferString, AvailableBytes);
    CurrentProc.Output.Read(BufferString[1], AvailableBytes);

    // Gabungkan teks baru ke Memo log
    TargetMemo.Text := TargetMemo.Text + BufferString;

    // Auto-scroll otomatis ke baris paling bawah layaknya PowerShell
    TargetMemo.SelStart := Length(TargetMemo.Text);
  end;
end;

procedure TServiceManagerForm.OnProcessTerminate(Sender: TObject);
var
  CurrentProc: TAsyncProcess;
begin
  CurrentProc := TAsyncProcess(Sender);
  if CurrentProc = FProcEmbed then
    memLogEmbed.Lines.Add(LineEnding + '>> [System] Proses llama-server (8081) keluar.')
  else
    memLogLLM.Lines.Add(LineEnding + '>> [System] Proses llama-server (8082) keluar.');

  UpdateUIState;
end;

end.
