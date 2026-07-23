unit uFaqForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  uFaqService, uEmbeddingService;

type

  { TFaqForm }

  TFaqForm = class(TForm)
    btnSimpan: TButton;
    btnBatal: TButton;
    edtTanya: TEdit;
    edtReferensi: TEdit;
    lblReferensi: TLabel;
    lblJawaban: TLabel;
    lblTanya: TLabel;
    memJawaban: TMemo;
    procedure btnBatalClick(Sender: TObject);
    procedure btnSimpanClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FFaqService: TFaqService;
    FEmbeddingService: TEmbeddingService;
    procedure ClearFields;
  public

  end;

var
  FaqForm: TFaqForm;

implementation

{$R *.lfm}

{ TFaqForm }

procedure TFaqForm.FormCreate(Sender: TObject);
begin
  FFaqService := TFaqService.Create;
  FEmbeddingService := TEmbeddingService.Create('http://localhost:8081');
end;

procedure TFaqForm.FormDestroy(Sender: TObject);
begin
  FFaqService.Free;
  FEmbeddingService.Free;
end;

procedure TFaqForm.ClearFields;
begin
  edtTanya.Text := '';
  memJawaban.Text := '';
  edtReferensi.Text := '';
end;

procedure TFaqForm.btnBatalClick(Sender: TObject);
begin
  Close;
end;

procedure TFaqForm.btnSimpanClick(Sender: TObject);
begin
  if (Trim(edtTanya.Text) = '') or (Trim(memJawaban.Text) = '') then
  begin
    ShowMessage('Pertanyaan dan Jawaban wajib diisi!');
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    if FFaqService.AddFaq(Trim(edtTanya.Text), Trim(memJawaban.Text), Trim(edtReferensi.Text), FEmbeddingService) then
    begin
      ShowMessage('Data FAQ dan Vektor berhasil disimpan.');
      ClearFields;
    end
    else
      ShowMessage('Gagal menyimpan data FAQ.');
  except
    on E: Exception do
      ShowMessage('Error: ' + E.Message);
  end;
  Screen.Cursor := crDefault;
end;

end.
