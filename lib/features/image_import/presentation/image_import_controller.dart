import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_picker_service.dart';
import '../services/image_rotation_service.dart';
import '../services/ocr_result.dart';
import '../services/ocr_text_formatter.dart';
import '../services/text_recognition_service.dart';

/// Creates the image used to preview a picked file.
typedef PreviewImageBuilder = ImageProvider Function(XFile file);

ImageProvider fileImageProvider(XFile file) => FileImage(File(file.path));

/// One successful pick or recovery. The id tells apart two selections of the
/// same file.
class ImageSelection {
  const ImageSelection(this.id, this.file, this.image);

  final int id;
  final XFile file;
  final ImageProvider image;
}

/// A file chosen in the gallery that is not applied yet. The screen may ask
/// the user for confirmation, then must call exactly one of
/// [ImageImportController.applyPick] or [ImageImportController.discardPick].
class PickCandidate {
  PickCandidate._(this._id, this.file);

  final int _id;
  final XFile file;
}

/// State and async flows of the image import screen.
///
/// It knows nothing about widgets, dialogs or [BuildContext]. Flows that need
/// a confirmation are split in two: the screen asks, then calls the
/// controller with the [revision] it read before asking. If the state changed
/// while the user was deciding, the call is ignored.
///
/// The controller owns [textController] (creation, listener and dispose).
/// After [dispose] every method is a no-op. A running native OCR call is not
/// cancelled; its result is dropped, and the temporary rotated copy of that
/// run is still deleted when the call finishes.
class ImageImportController extends ChangeNotifier {
  ImageImportController({
    required this.pickerService,
    required this.textRecognitionService,
    required this.rotationService,
    required this.previewImageBuilder,
  }) {
    textController.addListener(_onTextChanged);
  }

  final ImagePickerService pickerService;
  final TextRecognitionService textRecognitionService;
  final ImageRotationService rotationService;
  final PreviewImageBuilder previewImageBuilder;

  /// The text shown in the editable field. Owned and disposed here.
  final TextEditingController textController = TextEditingController();

  ImageSelection? _selection;
  int _quarterTurns = 0;
  int _lastSelectionId = 0;
  int _lastPickId = 0;
  int? _pendingPickId;
  int _revision = 0;
  int _recognitionId = 0;
  bool _isPicking = false;
  bool _isRecognizing = false;
  bool _disposed = false;

  /// Text last placed in the field by the app (OCR or joined text); null when
  /// there is no OCR result. Used to tell whether the user edited the text.
  String? _generatedText;

  /// Unmodified OCR result of the current image; the line-joined text is
  /// always derived from it.
  OcrResult? _ocrResult;
  bool _joinLines = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _lastHasEditedText = false;

  ImageSelection? get selection => _selection;
  bool get hasImage => _selection != null;

  /// Clockwise quarter turns (0-3) applied to the preview and to OCR input.
  /// Reset for every new selection.
  int get quarterTurns => _quarterTurns;
  bool get isPicking => _isPicking;
  bool get isRecognizing => _isRecognizing;
  bool get isBusy => _isPicking || _isRecognizing;
  bool get hasRecognizedText => _generatedText != null;
  bool get joinLines => _joinLines;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  /// Changes whenever the image, rotation or OCR text state changes in a way
  /// that makes an earlier confirmation stale. Typing does not change it.
  int get revision => _revision;

  /// Increases only when a new, non-empty OCR result has been applied to the
  /// text field. Errors, empty results, joining lines and rebuilds leave it
  /// unchanged, so the screen can react to new results (e.g. scroll).
  int get recognitionId => _recognitionId;

  /// True when the user changed the text after OCR (or typed it themselves).
  bool get hasEditedText {
    if (_disposed) return false;
    final text = textController.text;
    return text.isNotEmpty && text != _generatedText;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onTextChanged() {
    final edited = hasEditedText;
    if (edited == _lastHasEditedText) return;
    _lastHasEditedText = edited;
    _notify();
  }

  /// Replaces the image and drops everything tied to the old one: rotation,
  /// OCR result, join option and text. Must not be called while disposed.
  void _replaceSelection(ImageSelection? selection) {
    _selection = selection;
    _quarterTurns = 0;
    _generatedText = null;
    _ocrResult = null;
    _joinLines = false;
    textController.clear();
    _revision++;
  }

  /// Applies an image left by an Android activity restart. Needs no
  /// confirmation because nothing can have been edited yet.
  Future<void> recoverLostImage() async {
    if (_disposed || !pickerService.canRecoverLostImage) return;
    _isPicking = true;
    XFile? recovered;
    String? error;
    try {
      recovered = await pickerService.retrieveLostImage();
    } catch (_) {
      error = 'Önceki fotoğraf seçimi kurtarılamadı. Lütfen tekrar seçin.';
    }
    if (_disposed) return;
    _isPicking = false;
    if (recovered != null) {
      _replaceSelection(
        ImageSelection(
          ++_lastSelectionId,
          recovered,
          previewImageBuilder(recovered),
        ),
      );
    }
    _errorMessage = error;
    _notify();
  }

  /// Opens the gallery. Returns null when busy, cancelled or failed (the
  /// failure is in [errorMessage]); the busy state is then already released.
  /// On a result the busy state stays on until [applyPick] or [discardPick].
  Future<PickCandidate?> pickImage() async {
    if (_disposed || isBusy) return null;
    _isPicking = true;
    _errorMessage = null;
    _infoMessage = null;
    _notify();
    XFile? picked;
    String? error;
    try {
      picked = await pickerService.pickFromGallery();
    } catch (_) {
      error = 'Görsel seçilemedi. Lütfen tekrar deneyin.';
    }
    if (_disposed) return null;
    if (picked == null) {
      // A cancelled pick keeps the current image and text.
      _isPicking = false;
      _errorMessage = error;
      _notify();
      return null;
    }
    final id = ++_lastPickId;
    _pendingPickId = id;
    return PickCandidate._(id, picked);
  }

  /// Applies a confirmed candidate. Returns false (and changes nothing) when
  /// the candidate is no longer the pending one.
  bool applyPick(PickCandidate candidate) {
    if (_disposed || _pendingPickId != candidate._id) return false;
    _pendingPickId = null;
    _isPicking = false;
    _replaceSelection(
      ImageSelection(
        ++_lastSelectionId,
        candidate.file,
        previewImageBuilder(candidate.file),
      ),
    );
    _errorMessage = null;
    _notify();
    return true;
  }

  /// Drops a candidate (declined confirmation or closed screen). The current
  /// image and text stay as they are.
  void discardPick(PickCandidate candidate) {
    if (_disposed || _pendingPickId != candidate._id) return;
    _pendingPickId = null;
    _isPicking = false;
    _notify();
  }

  /// Only drops the reference. File ownership and cleanup are not managed yet,
  /// so nothing is deleted.
  void removeImage({required int expectedRevision}) {
    if (_disposed || isBusy || expectedRevision != _revision) return;
    _replaceSelection(null);
    _errorMessage = null;
    _infoMessage = null;
    _notify();
  }

  /// Ignores errors that belong to a selection that is no longer active. The
  /// text is kept: the user may have edited it.
  void onPreviewError(int selectionId) {
    if (_disposed || _selection?.id != selectionId) return;
    _selection = null;
    _revision++;
    _errorMessage = 'Görsel görüntülenemedi. Lütfen başka bir görsel seçin.';
    _infoMessage = null;
    _notify();
  }

  /// Rotates the image used for the preview and for the next OCR run. The
  /// recognized or edited text is kept.
  void rotate(int delta) {
    if (_disposed || _selection == null || isBusy) return;
    _quarterTurns = (_quarterTurns + delta) % 4;
    _revision++;
    _errorMessage = null;
    _infoMessage = null;
    _notify();
  }

  /// Shows the text derived from the raw OCR result, joined or not. Edits are
  /// replaced, so the screen must have confirmed first. [_generatedText]
  /// follows the displayed generated text, which keeps edit detection correct.
  void setJoinLines(bool value, {required int expectedRevision}) {
    final ocr = _ocrResult;
    if (_disposed || isBusy || ocr == null || expectedRevision != _revision) {
      return;
    }
    final display = value ? joinOcrResult(ocr) : ocr.text;
    _joinLines = value;
    _generatedText = display;
    textController.value = TextEditingValue(text: display);
    _revision++;
    _notify();
  }

  /// Runs OCR on the original file (or on a rotated temporary copy owned by
  /// this run). The screen confirms an overwrite of edited text first.
  Future<void> extractText({required int expectedRevision}) async {
    final selection = _selection;
    if (_disposed ||
        selection == null ||
        isBusy ||
        expectedRevision != _revision) {
      return;
    }

    _isRecognizing = true;
    _errorMessage = null;
    _infoMessage = null;
    _notify();
    final quarterTurns = _quarterTurns;
    OcrResult? ocr;
    String? error;
    // Temporary rotated copy owned by this OCR run; deleted only after OCR has
    // finished, whether it succeeded, failed or the controller was disposed.
    String? rotatedPath;
    var rotationFailed = false;
    try {
      var inputPath = selection.file.path;
      if (quarterTurns != 0) {
        try {
          rotatedPath = await rotationService.createRotatedCopy(
            inputPath,
            quarterTurns,
          );
        } catch (_) {
          rotationFailed = true;
          rethrow;
        }
        inputPath = rotatedPath;
      }
      // Without rotation the original picked file is used, not the downscaled
      // preview.
      ocr = await textRecognitionService.recognizeText(inputPath);
    } catch (_) {
      error = rotationFailed
          ? 'Görsel döndürülemedi. Döndürmeyi değiştirip tekrar deneyebilirsin.'
          : 'Metin çıkarılamadı. Tekrar denemek için "Metni çıkar" düğmesine bas.';
    } finally {
      if (rotatedPath != null) {
        await rotationService.deleteCopy(rotatedPath);
      }
    }
    if (_disposed) return;
    if (_selection?.id != selection.id) {
      // The image went away while OCR was running; drop the result.
      _isRecognizing = false;
      _notify();
      return;
    }
    _isRecognizing = false;
    _errorMessage = error;
    if (ocr != null) {
      if (ocr.text.trim().isEmpty) {
        _infoMessage =
            'Görselde metin bulunamadı. Daha net veya daha yakın bir '
            'fotoğrafla "Metni çıkar" düğmesine tekrar basabilirsin.';
      } else {
        _generatedText = ocr.text;
        _ocrResult = ocr;
        _joinLines = false;
        textController.value = TextEditingValue(text: ocr.text);
        _revision++;
        _recognitionId++;
      }
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    textController
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }
}
