import JPEG
import SolidJPEG
import Testing

@Suite
struct JPEGOracleTests {

  @Test
  func oracleDependencyIsAvailableOnlyWhenRequested() {
    let _: JPEG.Common = .y8
  }

}
