import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum ServerJoinError: Error, Equatable, Sendable { case invalidCard(String), insecureURL, hostNotAllowed(String), sizeLimit, pathTraversal(String), invalidDeepLink, signatureInvalid, keyChanged, hashMismatch, filesystem(String), download(String) }
public struct ServerAddress: Codable, Equatable, Sendable { public let host:String; public let port:Int; public init(host:String,port:Int){self.host=host;self.port=port} }
public enum Loader: String, Codable, Sendable { case vanilla,fabric,quilt,forge,neoforge }
public struct LoaderRequirement: Codable, Equatable, Sendable { public let type:Loader; public let version:String }
public struct PackRequirement: Codable, Equatable, Sendable { public let type:String; public let url:URL; public let sha512:String; public let version:String; public let sizeBytes:Int64?; enum CodingKeys:String,CodingKey {case type,url,sha512,version;case sizeBytes="size_bytes"} }
public struct CardSecurity: Codable, Equatable, Sendable { public let origin:URL; public let allowedHosts:[String]; public let trust:String; public let maxBytes:Int64; enum CodingKeys:String,CodingKey {case origin,allowedHosts="allowed_hosts",trust,maxBytes="max_bytes"} }
public struct SigningInfo: Codable, Equatable, Sendable { public let algorithm:String; public let keyID:String; public let publicKey:String; public let signature:String; public let previousKeySignature:String?; enum CodingKeys:String,CodingKey {case algorithm,keyID="key_id",publicKey="public_key",signature,previousKeySignature="previous_key_signature"} }
public struct ContentItem: Codable, Equatable, Sendable { public let id:String; public let name:String?; public let required:Bool?; public let sizeBytes:Int64?; public init(id:String,name:String?=nil,required:Bool?=nil,sizeBytes:Int64?=nil){self.id=id;self.name=name;self.required=required;self.sizeBytes=sizeBytes} }
public struct IOSOverrides: Codable, Equatable, Sendable { public let exclude:[String]; public let replace:[Replacement]; public struct Replacement: Codable,Equatable,Sendable {public let id:String;public let with:String} }
public struct PlatformOverrides: Codable, Equatable, Sendable { public let ios:IOSOverrides? }
public struct ServerCard: Codable, Equatable, Sendable {
 public let schemaVersion:String; public let id:String; public let server:Server; public let game:Game; public let loader:LoaderRequirement; public let pack:PackRequirement; public let content:Content?; public let recommendedRAMMB:Int?; public let platformOverrides:PlatformOverrides?; public let updatePolicy:String; public let security:CardSecurity; public let signing:SigningInfo; public let changelog:String?
 public struct Server:Codable,Equatable,Sendable {public let name:String;public let addresses:[ServerAddress];public let icon:URL?; public let network:String?}
 public struct Game:Codable,Equatable,Sendable {public let version:String;public let javaVersion:Int; enum CodingKeys:String,CodingKey {case version;case javaVersion="java_version"}}
 public struct Content:Codable,Equatable,Sendable {public let resourcePacks:[ContentItem]?;public let shaders:[ContentItem]?;public let clientMods:[ContentItem]?;public let optionalMods:[ContentItem]?; enum CodingKeys:String,CodingKey {case resourcePacks,shaders,clientMods,optionalMods}}
 enum CodingKeys:String,CodingKey {case schemaVersion="schema_version",id,server,game,loader,pack,content,recommendedRAMMB="recommended_ram_mb",platformOverrides="platform_overrides",updatePolicy="update_policy",security,signing,changelog}
}

public enum CardDecoder {
 public static func decode(_ data:Data, source:URL?=nil) throws -> ServerCard {
  guard data.count <= 512*1024 else {throw ServerJoinError.sizeLimit}
  let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
  let allowed:Set<String>=["schema_version","id","server","game","loader","pack","content","recommended_ram_mb","min_launcher_version","platform_overrides","changelog","update_policy","security","signing"]
  if !Set(obj.keys).isSubset(of: allowed) {throw ServerJoinError.invalidCard("unknown fields")}
  let card:ServerCard
  do {card=try JSONDecoder().decode(ServerCard.self,from:data)} catch {throw ServerJoinError.invalidCard(error.localizedDescription)}
  guard card.schemaVersion=="1.0.0", card.id.range(of:"^[a-z0-9][a-z0-9.-]{0,62}$",options:.regularExpression) != nil else {throw ServerJoinError.invalidCard("schema/id")}
  guard card.security.origin.scheme=="https", card.pack.url.scheme=="https", card.signing.algorithm=="ed25519", card.signing.publicKey.count==43, card.signing.signature.count==86 else {throw ServerJoinError.insecureURL}
  guard !card.security.allowedHosts.contains(where:{$0.contains("*")}), card.security.allowedHosts.allSatisfy({$0.range(of:"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$",options:.regularExpression) != nil}) else {throw ServerJoinError.invalidCard("wildcard host")}
  guard card.security.allowedHosts.contains(card.pack.url.host ?? ""), card.security.allowedHosts.contains(card.security.origin.host ?? "") else {throw ServerJoinError.hostNotAllowed(card.pack.url.host ?? "")}
  guard card.pack.sha512.range(of:"^[A-Fa-f0-9]{128}$",options:.regularExpression) != nil, (card.pack.sizeBytes ?? 0) <= 2_147_483_648 else {throw ServerJoinError.invalidCard("pack hash/size")}
  if let p=card.platformOverrides, let ios=p.ios { for x in ios.exclude where x.contains("..") || x.hasPrefix("/") {throw ServerJoinError.pathTraversal(x)} }
  return card
 }
}

public protocol CardFetcher: Sendable { func fetch(_ url:URL) async throws -> Data }
public struct URLSessionCardFetcher: CardFetcher { public init(){}; public func fetch(_ url:URL) async throws -> Data { let (d,r)=try await URLSession.shared.data(from:url); guard (r as? HTTPURLResponse)?.statusCode == 200 else {throw ServerJoinError.download("HTTP")}; return d } }
public enum Discovery { public static func deepLink(_ url:URL) throws -> URL { guard url.scheme=="cofre",url.host=="join",let raw=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="card"})?.value,let u=URL(string:raw),u.scheme=="https" else {throw ServerJoinError.invalidDeepLink}; return u }; public static func wellKnown(host:String)->URL { URL(string:"https://\(host)/.well-known/minecraft-server-card.json")! }; public static func fetchCard(from url:URL, using f:CardFetcher) async throws -> ServerCard { try CardDecoder.decode(try await f.fetch(url),source:url) } }

public struct TrustRecord: Codable,Equatable,Sendable {public let origin:String;public let keyID:String;public let fingerprint:String}
public protocol TrustStore: Sendable { func record(for origin:String) async -> TrustRecord?; func save(_ record:TrustRecord) async }
public actor MemoryTrustStore: TrustStore { private var records:[String:TrustRecord]=[:]; public init(){}; public func record(for origin:String)->TrustRecord?{records[origin]}; public func save(_ r:TrustRecord){records[r.origin]=r} }
public struct TrustDecision: Equatable,Sendable {public let firstVisit:Bool;public let origin:String;public let fingerprint:String}
public enum TrustVerifier {
 public static func evaluate(_ card:ServerCard, store:TrustStore) async throws -> TrustDecision { let origin=card.security.origin.absoluteString; let fp=card.signing.publicKey; if let old=await store.record(for:origin) { guard old.fingerprint==fp else {throw ServerJoinError.keyChanged}; return TrustDecision(firstVisit:false,origin:origin,fingerprint:fp) }; return TrustDecision(firstVisit:true,origin:origin,fingerprint:fp) }
 public static func confirm(_ card:ServerCard, store:TrustStore) async { await store.save(TrustRecord(origin:card.security.origin.absoluteString,keyID:card.signing.keyID,fingerprint:card.signing.publicKey)) }
 public static func verifySignature(card:ServerCard, canonicalData:Data?=nil) throws {
#if canImport(CryptoKit) && !os(Linux)
  guard let raw=Data(base64URLEncoded:card.signing.publicKey), let sig=Data(base64URLEncoded:card.signing.signature), let key=try? Curve25519.Signing.PublicKey(rawRepresentation:raw) else { throw ServerJoinError.signatureInvalid }
  guard key.isValidSignature(sig, for: canonicalData ?? Data()) else { throw ServerJoinError.signatureInvalid }
#else
  throw ServerJoinError.signatureInvalid
#endif
 }
}
private extension Data { init?(base64URLEncoded s:String){self.init(base64Encoded:s.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/").padding(toLength:((s.count+3)/4)*4,withPad:"=",startingAt:0))} }

public struct MrpackFile: Codable,Equatable,Sendable {public let path:String;public let hashes:[String:String];public let downloads:[URL];public let fileSize:Int64?;public let env:[String:String]?; enum CodingKeys:String,CodingKey {case path,hashes,downloads;case fileSize="fileSize";case env}}
public struct MrpackIndex: Codable,Equatable,Sendable {public let dependencies:[String:String];public let files:[MrpackFile]}
public struct InstallEntry: Equatable,Sendable {public let path:String;public let sizeBytes:Int64;public let required:Bool;public let manual:Bool}
public struct InstallPlan: Equatable,Sendable {public struct ReplacementPair: Equatable,Sendable {public let id:String;public let replacement:String}; public let loader:LoaderRequirement;public let gameVersion:String;public let javaVersion:Int;public let entries:[InstallEntry];public let totalDownloadSize:Int64;public let excluded:[String];public let replacements:[ReplacementPair]}
public enum InstallPlanner { public static func plan(card:ServerCard,index:MrpackIndex,ios:Bool=true)->InstallPlan { var excluded=ios ? (card.platformOverrides?.ios?.exclude ?? []) : []; var repl: [InstallPlan.ReplacementPair] = ios ? (card.platformOverrides?.ios?.replace ?? []).map{InstallPlan.ReplacementPair(id:$0.id,replacement:$0.with)} : []; var out:[InstallEntry]=[]; for f in index.files { if excluded.contains(f.path)||excluded.contains(f.path.split(separator:"/").last.map(String.init) ?? "") {continue}; let manual=f.path.contains("curseforge") || f.downloads.contains(where:{$0.host?.contains("curseforge") == true}); out.append(InstallEntry(path:f.path,sizeBytes:f.fileSize ?? 0,required:true,manual:manual)) }; for r in repl { out.removeAll{$0.path.contains(r.replacement)} }; return InstallPlan(loader:card.loader,gameVersion:card.game.version,javaVersion:card.game.javaVersion,entries:out,totalDownloadSize:out.reduce(0){$0+$1.sizeBytes},excluded:excluded,replacements:repl) } }

public struct UpdateDiff: Equatable,Sendable {public let added:[String];public let updated:[String];public let removed:[String];public let downloadSize:Int64}
public enum UpdateDiffer { public static func diff(old:MrpackIndex,new:MrpackIndex)->UpdateDiff {let a=Dictionary(uniqueKeysWithValues:old.files.map{($0.path,$0)}),b=Dictionary(uniqueKeysWithValues:new.files.map{($0.path,$0)});let added=b.keys.filter{a[$0]==nil};let removed=a.keys.filter{b[$0]==nil};let updated=b.keys.filter{if let x=a[$0],let y=b[$0]{return x.hashes != y.hashes};return false};return UpdateDiff(added:added.sorted(),updated:updated.sorted(),removed:removed.sorted(),downloadSize:updated.compactMap{b[$0]?.fileSize}.reduce(0,+)+added.compactMap{b[$0]?.fileSize}.reduce(0,+))} }

public protocol JoinFileSystem: Sendable { func makeStaging(_ id:String) throws; func write(_ data:Data,at path:String) throws; func atomicSwap(_ id:String) throws; func rollback(_ id:String) throws; func removeStaging(_ id:String) throws }
public protocol JoinDownloader: Sendable { func download(_ url:URL,resumeData:Data?) async throws -> (Data,Data?) }
public actor InstallEngine { public init(){}; public func install(card:ServerCard,data:Data,filesystem:JoinFileSystem,downloader:JoinDownloader) async throws { try filesystem.makeStaging(card.id); do { guard data.count <= 2_147_483_648 else {throw ServerJoinError.sizeLimit}; try filesystem.write(data,at:"pack.mrpack"); try filesystem.atomicSwap(card.id) } catch { try? filesystem.removeStaging(card.id); try? filesystem.rollback(card.id); throw error } } }

public struct SelectableContentItem: Identifiable,Equatable,Sendable {public let id:String;public let name:String;public let detail:String?;public let sizeBytes:Int64;public var isSelected:Bool;public let isRequired:Bool;public init(id:String,name:String,detail:String?=nil,sizeBytes:Int64,isSelected:Bool,isRequired:Bool){self.id=id;self.name=name;self.detail=detail;self.sizeBytes=sizeBytes;self.isSelected=isSelected;self.isRequired=isRequired}}
public enum CheckState:Equatable,Sendable {case checking,ready,failed(String)}
public struct ServerJoinRequirementsState:Equatable,Sendable {public let serverID:String;public let serverName:String;public let serverAddress:String;public let iconURL:URL?;public let motd:String?;public let pingMS:Int?;public let gameVersion:String;public let loader:Loader;public let loaderVersion:String;public let javaMajorVersion:Int;public let packName:String;public let packVersion:String;public let totalDownloadSizeBytes:Int64;public let formattedDownloadSize:String;public let estimatedDownloadSeconds:Int?;public let requiredModCount:Int;public let optionalMods:[SelectableContentItem];public let resourcePacks:[SelectableContentItem];public let shaderPacks:[SelectableContentItem];public let recommendedRAMMB:Int;public let deviceRAMMB:Int;public let isNewProfile:Bool}
public struct ServerJoinWarningState:Equatable,Sendable {public enum WarningSeverity:Sendable{case notice,performance,security,blocking};public struct WarningItem:Identifiable,Equatable,Sendable{public let id:String;public let severity:WarningSeverity;public let title:String;public let message:String;public let actionLabel:String?;public let actionURL:URL?};public let warnings:[WarningItem];public let canProceedAnyway:Bool}
public struct InstallStage:Identifiable,Equatable,Sendable{public let id:Int;public let title:String;public let state:CheckState;public let detail:String?}
public struct ServerJoinInstallingState:Equatable,Sendable{public let title:String;public let progressFraction:Double;public let formattedProgress:String;public let speedFormatted:String?;public let timeRemainingSeconds:Int?;public let stages:[InstallStage];public let currentStageIndex:Int;public let canCancel:Bool}
public struct ModUpdateSummary:Identifiable,Equatable,Sendable{public let id:String;public let name:String;public let fromVersion:String;public let toVersion:String}
public struct ServerJoinUpdateState:Equatable,Sendable{public let serverID:String;public let currentVersion:String;public let newVersion:String;public let changelogText:String?;public let changelogURL:URL?;public let isBreakingChange:Bool;public let addedMods:[String];public let removedMods:[String];public let updatedMods:[ModUpdateSummary];public let downloadSizeBytes:Int64}
public enum RecoveryAction:Sendable,Equatable{case retry,openSettingsStorage,triggerJITWorkflow,openCurseForgeWeb(url:URL,expectedHash:String),contactServerAdmin,dismiss}
public struct ServerJoinErrorState:Equatable,Sendable{public enum ErrorCode:String,Sendable{case networkTimeout="ERR_NET_TIMEOUT",hostNotFound="ERR_HOST_NOT_FOUND",checksumMismatch="ERR_CHECKSUM_MISMATCH",storageFull="ERR_STORAGE_FULL",jitMissing="ERR_JIT_UNMOUNTED",signatureRejected="ERR_SIGNATURE_REJECTED",pathTraversalDetected="ERR_SECURITY_PATH_TRAVERSAL",curseForgeRestricted="ERR_CURSEFORGE_RESTRICTED"};public let code:ErrorCode;public let title:String;public let message:String;public let recoveryAction:RecoveryAction}
public struct ServerJoinReadyState:Equatable,Sendable{public let serverID:String;public let serverName:String;public let serverAddress:String;public let instanceID:String;public let isJITReady:Bool;public var autoConnectOnLaunch:Bool;public let primaryButtonTitle:String}
