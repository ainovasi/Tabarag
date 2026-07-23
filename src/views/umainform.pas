unit uMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, process,
  Menus, ComCtrls, JwaWindows, contnrs,strutils, DateUtils,         // Diperlukan untuk memproses TFPObjectList hasil pencarian
  uDBConnection,    // Pengelola koneksi SQLite dan ekstensi vektor
  uDBTables,        // Pengelola pembuatan tabel otomatis
  uFaqService,      // Penyedia metode HybridSearch (RRF)
  uEmbeddingService,// Penghubung ke Llama Server BGE-M3 (Port 8081)
  uChatLLMService,   // Penghubung ke Llama Server Gemma 3 (Port 8082)
  uFaqForm,
  uFaqListForm,
  AsyncProcess, ATLinkLabel,
  uServiceManagerForm,
  uFaqModel;        // Definisi struktur data TFaqSearchResult

type

  { TMainForm }

  TMainForm = class(TForm)
    btnKirim: TButton;
    btnRAGAdmin: TButton;
    btnReload: TButton;
    btnOpenParameter: TButton;
    btnChat: TButton;
    btnLogPrompt: TButton;
    cbListGGUF: TComboBox;
    edtInput: TEdit;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    GroupBox3: TGroupBox;
    GroupBox4: TGroupBox;
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    lbJumlahData: TLabel;
    lblbgeRamStatus: TLabel;
    lblGemmaRamStatus: TLabel;
    lblRamStatus: TLabel;
    memChat: TMemo;
    memLogEmbed: TMemo;
    memLogLLM: TMemo;
    mmPrompt: TMemo;
    Panel5: TPanel;
    pgMain: TPageControl;
    Panel1: TPanel;
    Panel4: TPanel;
    pgRight: TPageControl;
    pnlBottom: TPanel;
    pnlEmbedHeader: TPanel;
    pnlLLMHeader: TPanel;
    tbsContext: TTabSheet;
    tbsLogLLM: TTabSheet;
    tbsLogBEG: TTabSheet;
    tbsChat: TTabSheet;
    tbsData: TTabSheet;
    tbsMonitoring: TTabSheet;
    TimerRam: TTimer;
    procedure btnChatClick(Sender: TObject);
    procedure btnKelolaFaqClick(Sender: TObject);
    procedure btnKirimClick(Sender: TObject);
    procedure btnLogPromptClick(Sender: TObject);
    procedure btnOpenParameterClick(Sender: TObject);
    procedure btnRAGAdminClick(Sender: TObject);
    procedure btnReloadClick(Sender: TObject);
    procedure btnStartServerEmbedingClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure cbListGGUFChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure MenuItem4Click(Sender: TObject);
    procedure mnFAQAddClick(Sender: TObject);
    procedure mnKeluarClick(Sender: TObject);
    procedure mnShowChatClick(Sender: TObject);
    procedure mnShowDataClick(Sender: TObject);
    procedure tbsChatShow(Sender: TObject);
    procedure tbsContextShow(Sender: TObject);
    procedure tbsDataShow(Sender: TObject);
    procedure TimerRamTimer(Sender: TObject);
  private

    FFaqService: TFaqService;
    FFServiceManager : TServiceManagerForm;
    FProcLLM: TAsyncProcess;
    FProcEmbed: TAsyncProcess;

    FEmbeddingService: TEmbeddingService; // Mesin Vektor BGE-M3 (8081)
    FChatLLMService: TChatLLMService;     // Mesin Generasi Gemma 3 (8082)
    FChatHistory: TStringList; // <-- TAMBAHKAN INI untuk menampung riwayat chat

    procedure OnProcessReadData(Sender: TObject);
    procedure OnProcessTerminate(Sender: TObject);
    procedure UpdateUIState;
    procedure SetupTerminalStyle(AMemo: TMemo);
    procedure StartServerBGE;
    procedure StartServerChat;

    procedure TampilkanRAGBuilder;
    procedure LoadGGUFFiles;
    procedure SetLLMChatParameter(g:string);
    procedure KillAllServer;
  public

    function IsLLMRunning: Boolean;
    function GetLLMProcessID: DWORD;

    function IsBGERunning: Boolean;
    function GetBGEProcessID: DWORD;
    function GetRamUsageByPID(AProcessID: DWORD): UInt64;
  end;

  SIZE_T = NativeUInt;

    TProcessMemoryCounters = record
      cb: DWORD;
      PageFaultCount: DWORD;
      PeakWorkingSetSize: SIZE_T;
      WorkingSetSize: SIZE_T; // Kolom target RAM fisik
      QuotaPeakPagedPoolUsage: SIZE_T;
      QuotaPagedPoolUsage: SIZE_T;
      QuotaPeakNonPagedPoolUsage: SIZE_T;
      QuotaNonPagedPoolUsage: SIZE_T;
      PagefileUsage: SIZE_T;
      PeakPagefileUsage: SIZE_T;
    end;

  function GetProcessMemoryInfo(hProcess: HANDLE; pmemCounters: Pointer; cb: DWORD): LongBool; stdcall; external 'psapi.dll' name 'GetProcessMemoryInfo';

var
  MainForm: TMainForm;
  StrParameter:TStringList;
  durasi : Double=0;

implementation

{$R *.lfm}

type
  { TLLMChatThread: Kelas Pekerja Latar Belakang agar UI Anti-Freeze }
  TLLMChatThread = class(TThread)
  private
    FUserQuery: String;
    FHistoryText: String;
    FContextData: String;
    FLlmResponse: String;
    FIsSuccess: Boolean;
    FErrorMessage: String;
    procedure SyncUpdateUI;
  protected
    procedure Execute; override;
  public
    constructor Create(const AQuery, AHistory: String);
    function CleanMarkdown(const AText: String): String;
  end;

{ TLLMChatThread Implementation }

constructor TLLMChatThread.Create(const AQuery, AHistory: String);
begin
  inherited Create(False); // Langsung eksekusi setelah dibuat
  FUserQuery := AQuery;
  FHistoryText := AHistory;
  FreeOnTerminate := True; // Otomatis hancurkan objek dari RAM saat tugas selesai
end;

procedure TLLMChatThread.Execute;
var
  SearchResult: TFPObjectList;
  FaqItem: TFaqSearchResult;
  SystemPrompt: String;
  i: Integer;
  WaktuMulai, WaktuSelesai: QWord;
begin
  FIsSuccess := False;
  FContextData := '';


  try
    // 1. Jalankan hybrid search ke database lokal di background thread
    SearchResult := MainForm.FFaqService.HybridSearch(FUserQuery, MainForm.FEmbeddingService, 3);
    try
      if Assigned(SearchResult) and (SearchResult.Count > 0) then
      begin
        for i := 0 to SearchResult.Count - 1 do
        begin
          FaqItem := TFaqSearchResult(SearchResult[i]);
          FContextData := FContextData + Format(
            '---' + LineEnding +
            'Kasus/Pertanyaan Regulasi: %s' + LineEnding +
            'Ketentuan Hukum Resmi: %s' + LineEnding +
            'Referensi Pasal/Undang-Undang: %s' + LineEnding,
            [FaqItem.Tanya, FaqItem.Jawaban, FaqItem.Referensi]
          );

        end;
      end;
    finally
      SearchResult.Free;
    end;


    {
    if MainForm.ckHistori.Checked then
    SystemPrompt :=
      'Anda adalah Asisten Pakar Perpajakan Indonesia yang dibekali memori ingatan percakapan. ' + LineEnding +
      'Jawablah pertanyaan terbaru USER dengan mempertimbangkan alur obrolan sebelumnya dan patuhi [Konteks Regulasi Baku] yang diberikan.' + LineEnding + LineEnding +
      'Jika tidak ada  [Konteks Regulasi Baku] maka Jawab "Pertanyaan Anda Tidak Tentang Perpajakan".' + LineEnding +
      '[Riwayat Percakapan Sebelumnya]:' + LineEnding +
      FHistoryText + LineEnding +
      '[Konteks Regulasi Baku]:' + LineEnding +
      FContextData
    else           }

    if Length(FContextData)< 10 then
    SystemPrompt:=
      'Jawab saja dengan kata "Maaf Saya tidak menemukan jawabannya Atau Tidak Terkait dengan konteks Perpajakan"'
    else
    SystemPrompt :=
      'Anda adalah Asisten Pakar Perpajakan Indonesia yang presisi dan patuh pada aturan.' + LineEnding +
      '=== ATURAN UTAMA & GUARDRAIL ===' + LineEnding +
      '1. Jawablah pertanyaan USER HANYA berdasarkan informasi yang terdapat di dalam [KKONTEKS REGULASI BAKU] di bawah ini.' + LineEnding +
      '2. DILARANG KERAS menggunakan pengetahuan di luar konteks yang diberikan untuk mencegah halusinasi hukum.' + LineEnding +
      LineEnding +
      '=== FORMAT OUTPUT (WAJIB) ===' + LineEnding +
      '- Tuliskan jawaban dalam format TEKS POLOS (Plain Text).' + LineEnding +
      '- DILARANG menggunakan karakter Markdown seperti bintang (** bold **), tanda pagar (### heading), atau backticks (`).' + LineEnding +
      '- Cantumkan Referensi UU/Pasal di akhir jawaban jika tersedia di dalam konteks.' + LineEnding +
      '=== KONTEKS REGULASI BAKU ===' + LineEnding +
      FContextData;


     MainForm.mmPrompt.text := SystemPrompt;

    WaktuMulai:=GetTickCount;


    // 3. Kirim data prompt ke layanan LLM Server (menunggu respon jaringan secara senyap)
    FLlmResponse := MainForm.FChatLLMService.GenerateAnswer(SystemPrompt, FUserQuery);
    FIsSuccess := True;
    WaktuSelesai:=GetTickCount;
    durasi := (WaktuSelesai - WaktuMulai) / 1000.0;
  except
    on E: Exception do
    begin
      FErrorMessage := E.Message;
    end;
  end;

  // Kembalikan hasil komputasi berat ke komponen UI utama secara sinkron & aman
  Synchronize(@SyncUpdateUI);
end;

procedure TLLMChatThread.SyncUpdateUI;
var
  FinalPrompt: String;
  CleanedResponse: String; // <-- Tambahkan variabel ini
begin
  // Hapus teks informasi penanda loading "(Sedang menganalisis konteks...)"
  if MainForm.memChat.Lines.Count > 0 then
    MainForm.memChat.Lines.Delete(MainForm.memChat.Lines.Count - 1);


  if FIsSuccess then
  begin

    CleanedResponse := CleanMarkdown(FLlmResponse);
    // Tampilkan jawaban AI ke layar chat utama
    MainForm.memChat.Lines.Add('ASSISTANT: ' + CleanedResponse );
    MainForm.memChat.Lines.Add('..........................................................................................');
    MainForm.memChat.Lines.Add('Model AI : ' + MainForm.cbListGGUF.text + '>'  + Format(' Waktu Eksekusi: %.3f detik', [durasi]));
    durasi := 0;

    // Masukkan ke dalam RAM History percakapan agar dapat dibaca di chat selanjutnya
    MainForm.FChatHistory.Add('ANDA: ' + FUserQuery);
    MainForm.FChatHistory.Add('ASSISTANT: ' + CleanedResponse);
  end
  else
  begin
    MainForm.memChat.Lines.Add('SYSTEM ERROR: ' + FErrorMessage);
    MainForm.memChat.Lines.Add('');
  end;

  // Buka kembali interaksi kontrol input setelah proses selesai
  MainForm.btnKirim.Enabled := True;
  MainForm.edtInput.Enabled := True;
  MainForm.edtInput.SetFocus;
end;

{ TMainForm Events & Methods }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  try
    TDBTables.InitializeDatabase;
    FFaqService := TFaqService.Create;

    // Instance Llama-Server 1: Mengarah ke Port 8080 untuk model BGE-M3
    FEmbeddingService := TEmbeddingService.Create('http://localhost:8080');

    // Instance Llama-Server 2: Mengarah ke Port 8081 untuk model Gemma 3
    FChatLLMService := TChatLLMService.Create('http://localhost:8081');
    FChatLLMService.Temperature := 0.2;

    TimerRam.Interval := 1000;
    TimerRam.Enabled := True;
    TimerRamTimer(Self);

    memChat.Lines.Clear;
    memChat.Lines.Add('..........................................................................................');
    memChat.Lines.Add('>>> Sistem TaxRAG Lokal Aktif.');
    memChat.Lines.Add('>>> Engine Vektor: BGE-M3 GGUF (Port 8080)');
    memChat.Lines.Add('>>> Engine Penalaran: LLAMA (Port 8081)');
    memChat.Lines.Add('..........................................................................................');
    memChat.Lines.Add('');
  except
    on E: Exception do
      ShowMessage('Gagal menginisialisasi sistem RAG: ' + E.Message);
  end;

  FProcEmbed := TAsyncProcess.Create(nil);
  FProcEmbed.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcEmbed.OnReadData := @OnProcessReadData;
  FProcEmbed.OnTerminate := @OnProcessTerminate;

  FProcLLM := TAsyncProcess.Create(nil);
  FProcLLM.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcLLM.OnReadData := @OnProcessReadData;
  FProcLLM.OnTerminate := @OnProcessTerminate;

  SetupTerminalStyle(memLogEmbed);
  SetupTerminalStyle(memLogLLM);

  FChatHistory := TStringList.Create;
  UpdateUIState;
  pgRight.ShowTabs:=false;
  pgMain.ShowTabs:=false;
  pgMain.ActivePageIndex:= 0;
end;


procedure TMainForm.btnKirimClick(Sender: TObject);
var
  UserQuery, HistoryText: String;
begin
  UserQuery := Trim(edtInput.Text);
  if UserQuery = '' then Exit;

  // Kunci tombol UI sesaat agar tidak terjadi spam klik ganda oleh user
  btnKirim.Enabled := False;
  edtInput.Enabled := False;

  // Ambil data history dari RAM penampung
  HistoryText := FChatHistory.Text;
  if HistoryText = '' then
     HistoryText := '(Belum ada percakapan sebelumnya)';

  // Perbarui tampilan chat secara instan untuk respon cepat ke pengguna
  memChat.Lines.Add('ANDA: ' + UserQuery);
  memChat.Lines.Add('');
  edtInput.Text := '';

  memChat.Lines.Add('ASSISTANT: (Sedang menganalisis konteks...)');

  // OPER BEBAN KERJA KE BACKGROUND THREAD (Aplikasi bebas freeze!)
  TLLMChatThread.Create(UserQuery, HistoryText);
end;

procedure TMainForm.btnLogPromptClick(Sender: TObject);
begin
  tbsContext.show;
end;

procedure TMainForm.btnOpenParameterClick(Sender: TObject);
var
  ProcNotepad:TProcess;
  FolderPath,model:string ;
begin
  FolderPath := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName) + 'ai/model/');
  model := AnsiReplaceStr(cbListGGUF.text,'.gguf','.var');
  try
    ProcNotepad := TProcess.Create(self);
    ProcNotepad.Executable:='notepad';
    ProcNotepad.Parameters.Add(FolderPath + model);
    ProcNotepad.Execute;
  finally
  end;

end;

procedure TMainForm.btnRAGAdminClick(Sender: TObject);
begin
  tbsData.Show;
end;

function TMainForm.IsLLMRunning: Boolean;
begin
  Result := Assigned(FProcLLM) and FProcLLM.Running;
end;

procedure TMainForm.LoadGGUFFiles;
var
  SR: TSearchRec;
  FolderPath: String;
begin
  FolderPath := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName) + 'ai/model');
  if not DirectoryExists(FolderPath) then
  begin
    ShowMessage('Folder ' + FolderPath + ' tidak ditemukan. Silakan buat folder terlebih dahulu.');
    Exit;
  end;

  cbListGGUF.Items.BeginUpdate;
  try
    cbListGGUF.Items.Clear;
    if FindFirst(FolderPath + '*.gguf', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          cbListGGUF.Items.Add(SR.Name);
        end;
      until FindNext(SR) <> 0;
      SysUtils.FindClose(SR);
    end;
  finally
    cbListGGUF.Items.EndUpdate;
  end;




  if cbListGGUF.Items.Count > 0 then
    cbListGGUF.ItemIndex := 0
  else
    cbListGGUF.Text := '(Tidak ada file .gguf)';

  SetLLMChatParameter(cbListGGUF.Text) ;
end;

function TMainForm.GetLLMProcessID: DWORD;
begin
  if IsLLMRunning then
    Result := FProcLLM.ProcessID
  else
    Result := 0;
end;

function TMainForm.IsBGERunning: Boolean;
begin
  Result := Assigned(FProcEmbed ) and FProcEmbed.Running;
end;

function TMainForm.GetBGEProcessID: DWORD;
begin
  if IsBGERunning then
    Result := FProcEmbed.ProcessID
  else
    Result := 0;
end;

function TMainForm.GetRamUsageByPID(AProcessID: DWORD): UInt64;
var
  HProcess: HANDLE;
  PMC: TProcessMemoryCounters;
begin
  Result := 0;
  if AProcessID = 0 then Exit;

  HProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, AProcessID);
  if HProcess <> 0 then
  begin
    try
      FillChar(PMC, SizeOf(PMC), 0);
      PMC.cb := SizeOf(PMC);
      if GetProcessMemoryInfo(HProcess, @PMC, SizeOf(PMC)) then
      begin
        Result := PMC.WorkingSetSize;
      end;
    finally
      CloseHandle(HProcess);
    end;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin

  FFaqService.Free;
  FEmbeddingService.Free;
  FChatLLMService.Free;

  if FProcEmbed.Running then FProcEmbed.Terminate(0);
  if FProcLLM.Running then FProcLLM.Terminate(0);

  FChatHistory.Free;
  FProcEmbed.Free;
  FProcLLM.Free;

  inherited;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin

  StrParameter := TStringList.Create;

  TampilkanRAGBuilder;
  LoadGGUFFiles;
  StartServerChat;
  StartServerBGE;



end;

procedure TMainForm.MenuItem4Click(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TMainForm.mnFAQAddClick(Sender: TObject);
var
  FrmFaq: TFaqForm;
begin
  FrmFaq := TFaqForm.Create(Self);
  try
    FrmFaq.ShowModal;
  finally
    FrmFaq.Free;
  end;
end;

procedure TMainForm.mnKeluarClick(Sender: TObject);
begin
   if FProcLLM.Running then FProcLLM.Terminate(0);
   if FProcEmbed.Running then FProcEmbed.Terminate(0);
   Application.Terminate;
end;

procedure TMainForm.mnShowChatClick(Sender: TObject);
begin
  tbsChat.show;
end;

procedure TMainForm.mnShowDataClick(Sender: TObject);
begin
  tbsData.show;
end;

procedure TMainForm.tbsChatShow(Sender: TObject);
begin
 // btnChat.Hide;
end;

procedure TMainForm.tbsContextShow(Sender: TObject);
begin
  btnChat.Show;
end;

procedure TMainForm.tbsDataShow(Sender: TObject);
begin
  btnChat.Show;
end;

procedure TMainForm.TampilkanRAGBuilder;
var
   FFaqListForm :  TFaqListForm;
begin
    FFaqListForm := TFaqListForm.Create(Self);
    FFaqListForm.Parent:= tbsData;
    FFaqListForm.Align:=alClient;
    FFaqListForm.BorderStyle:=bsnone;
    FFaqListForm.Show;

    lbJumlahData.Caption:= 'Total : ' + Inttostr(FFaqListForm.qryFaq.RecordCount);
end;

procedure TMainForm.TimerRamTimer(Sender: TObject);
var
  MemStatus: TMemoryStatusEx;
  TotalPhysGB, UsedPhysGB: Double;
  GemmaPID: DWORD;
  GemmaBytes: UInt64;
  GemmaMB: Double;
  BGEPID: DWORD;
  BGEBytes: UInt64;
  BGEMB: Double;
begin
  MemStatus.dwLength := SizeOf(MemStatus);
  if GlobalMemoryStatusEx(MemStatus) then
  begin
    TotalPhysGB := MemStatus.ullTotalPhys / (1024 * 1024 * 1024);
    UsedPhysGB  := (MemStatus.ullTotalPhys - MemStatus.ullAvailPhys) / (1024 * 1024 * 1024);

    lblRamStatus.Caption := Format('Total Sistem RAM: %0.2f GB / %0.2f GB (%d%%)',
      [UsedPhysGB, TotalPhysGB, MemStatus.dwMemoryLoad]);
  end;

  GemmaMB := 0;
  if IsLLMRunning then
  begin
    GemmaPID := GetLLMProcessID;
    GemmaBytes := GetRamUsageByPID(GemmaPID);
    GemmaMB := GemmaBytes / (1024 * 1024);
  end;

  if GemmaMB > 0 then
  begin
    lblGemmaRamStatus.Caption := Format(cbListGGUF.text + ' Engine RAM: %0.2f MB', [GemmaMB]);
    lblGemmaRamStatus.Font.Color := clBlue;
  end
  else
  begin
    lblGemmaRamStatus.Caption := cbListGGUF.text + ' Engine RAM: Offline';
    lblGemmaRamStatus.Font.Color := clScrollBar;
  end;

  BGEMB := 0;
  if IsBGERunning then
  begin
    BGEPID := GetBGEProcessID;
    BGEBytes := GetRamUsageByPID(BGEPID);
    BGEMB := BGEBytes / (1024 * 1024);
  end;

  if BGEMB > 0 then
  begin
    lblbgeRamStatus.Caption := Format('Bge-m3  Engine RAM: %0.2f MB', [BGEMB]);
    lblbgeRamStatus.Font.Color := clBlue;
  end
  else
  begin
    lblbgeRamStatus.Caption := 'Bge-m3 RAM: Offline';
    lblbgeRamStatus.Font.Color := clScrollBar;
  end;
end;

procedure TMainForm.btnReloadClick(Sender: TObject);
begin

 KillAllServer;

 ShowMessage('Layanan LLama-Server Dihentikan');

 if FProcLLM.Running then FProcLLM.Terminate(0);
   Application.ProcessMessages;
   Sleep(1500);
   StartServerChat;



 if FProcEmbed.Running then FProcEmbed.Terminate(0);
   Application.ProcessMessages;
   Sleep(1500);
   StartServerBGE;

end;

procedure TMainForm.btnStartServerEmbedingClick(Sender: TObject);
begin
   StartServerBGE;
end;

procedure TMainForm.StartServerBGE;
var
  BaseDir: String;

begin
  BaseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + 'ai/');
  memLogEmbed.Clear;
  memLogEmbed.Lines.Add('>> Memulai Llama Server Embedding (Port 8080)...');

  FProcEmbed.Executable := BaseDir + 'llama-server.exe';
  FProcEmbed.Parameters.Clear;

  FProcEmbed.Parameters.Add('-m');
  FProcEmbed.Parameters.Add(ExpandFileName(BaseDir  + PathDelim + 'model' + PathDelim + 'embed' + PathDelim + 'bgem3.gguf'));

  FProcEmbed.Parameters.Add('--embedding');
  FProcEmbed.Parameters.Add('-c');
  FProcEmbed.Parameters.Add('8192');
  FProcEmbed.Parameters.Add('--port');
  FProcEmbed.Parameters.Add('8080');
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

procedure TMainForm.StartServerChat;
var
  BaseDir: String;
  model : string;
  i,j : integer;
begin
  BaseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) +'ai/');
  model := cbListGGUF.text;

  memLogLLM.Clear;
  memLogLLM.Lines.Add('>> Memulai Llama Server Gemma 3 (Port 8081)...');



  FProcLLM.Executable := BaseDir + 'llama-server.exe';
  FProcLLM.Parameters.Clear;
  FProcLLM.Parameters.Add('-m');
  FProcLLM.Parameters.Add(ExpandFileName(BaseDir  + PathDelim + 'model' + PathDelim + model));



  for i := 0 to StrParameter.Count-1 do
  begin
   FProcLLM.Parameters.Add(StrParameter.Strings[i])
  end;

  try
    FProcLLM.Execute;
    UpdateUIState;
  except
    on E: Exception do
      memLogLLM.Lines.Add('ERROR gagal menjalankan executable: ' + E.Message);
  end;
end;

procedure TMainForm.Button1Click(Sender: TObject);
begin
  FFServiceManager := TServiceManagerForm.Create(Self);
  try
    FFServiceManager.ShowModal;
  finally
    FFServiceManager.Free;
  end;
end;

procedure TMainForm.cbListGGUFChange(Sender: TObject);
begin
   SetLLMChatParameter(cbListGGUF.Text) ;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  

  application.Terminate;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsLLMRunning then
  begin
    FProcLLM.Terminate(0);
    while FProcLLM.Running do
    begin
      // Biarkan aplikasi tetap memproses antrean pesan Windows agar tidak hang
      Application.ProcessMessages;
      Sleep(10);
    end;
  end;

  // 3. MATIKAN SERVER BGE EMBEDDING DAN TUNGGU SAMPAI MATI
  if IsBGERunning then
  begin
    FProcEmbed.Terminate(0);
    while FProcEmbed.Running do
    begin
      Application.ProcessMessages;
      Sleep(10);
    end;
  end;

  CanClose := True; // Izinkan aplikasi ditutup dengan aman
end;

procedure TMainForm.SetLLMChatParameter(g:string);
var
  model:string;
  FolderPath: String;
begin
  model := AnsiReplaceStr(g,'.gguf','.var');
  FolderPath := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName) + 'ai/model');
  StrParameter.LoadFromFile(FolderPath + PathDelim + model);

end;

procedure TMainForm.btnKelolaFaqClick(Sender: TObject);
var
  FrmFaq: TFaqForm;
begin
  FrmFaq := TFaqForm.Create(Self);
  try
    FrmFaq.ShowModal;
  finally
    FrmFaq.Free;
  end;
end;

procedure TMainForm.btnChatClick(Sender: TObject);
begin
  tbsChat.Show;
end;

procedure TMainForm.OnProcessReadData(Sender: TObject);
var
  CurrentProc: TAsyncProcess;
  TargetMemo: TMemo;
  AvailableBytes: Integer;
  BufferString: String;
begin
  CurrentProc := TAsyncProcess(Sender);
  if CurrentProc = FProcEmbed then
    TargetMemo := memLogEmbed
  else
    TargetMemo := memLogLLM;

  AvailableBytes := CurrentProc.Output.NumBytesAvailable;
  if AvailableBytes > 0 then
  begin
    SetLength(BufferString, AvailableBytes);
    CurrentProc.Output.Read(BufferString[1], AvailableBytes);
    TargetMemo.Text := TargetMemo.Text + BufferString;
    TargetMemo.SelStart := Length(TargetMemo.Text);
  end;
end;

procedure TMainForm.OnProcessTerminate(Sender: TObject);
var
  CurrentProc: TAsyncProcess;
begin
  CurrentProc := TAsyncProcess(Sender);
  if CurrentProc = FProcEmbed then
    memLogEmbed.Lines.Add(LineEnding + '>> [System] Proses llama-server (8081) keluar.')
  else
    memLogLLM.Lines.Add(LineEnding + '>> [System] Proses llama-server (8080) keluar.');
  UpdateUIState;
end;

procedure TMainForm.UpdateUIState;
begin
end;

procedure TMainForm.SetupTerminalStyle(AMemo: TMemo);
begin
  AMemo.Color := TColor($1C140C);
  AMemo.Font.Name := 'vt323';
  AMemo.Font.Size := 9;
  AMemo.Font.Color := clLime;
  AMemo.ScrollBars := ssNone;
  AMemo.ReadOnly := True;
  AMemo.Alignment:=taLeftJustify;
end;


function TLLMChatThread.CleanMarkdown(const AText: String): String;
begin
  Result := AText;

  // 1. Hapus penanda Bold & Italic (**, ***, _, __)
  Result := StringReplace(Result, '***', '', [rfReplaceAll]);
  Result := StringReplace(Result, '**', '', [rfReplaceAll]);
  Result := StringReplace(Result, '___', '', [rfReplaceAll]);
  Result := StringReplace(Result, '__', '', [rfReplaceAll]);
  Result := StringReplace(Result, '_', '', [rfReplaceAll]);

  // 2. Hapus penanda kode / inline code (`)
  Result := StringReplace(Result, '`', '', [rfReplaceAll]);

  // 3. Hapus penanda Heading/Judul (###, ##, #)
  Result := StringReplace(Result, '### ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '## ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '# ', '', [rfReplaceAll]);

  // 4. Ubah bullet list markdown (*) menjadi strip rapi (-) agar enak dilihat di TMemo
  Result := StringReplace(Result, LineEnding + '* ', LineEnding + '- ', [rfReplaceAll]);
end;

procedure TMainForm.KillAllServer;
var
  procKill : TProcess;
begin

  try
    procKill := TProcess.Create(self);
    procKill.CommandLine:='taskkill /IM llama-server.exe /F';
    procKill.Parameters.Add('/IM');
    procKill.Parameters.Add('llama-server.exe');
    procKill.Parameters.Add('/F');
    procKill.Options:=[poUsePipes, poStderrToOutPut, poNoConsole];
    procKill.Execute;
  finally
    procKill.free
  end;


end;

end.
