//
//  SmaatoApplovinMediationAdapter.m
//  SmaatoSDKApplovinWaterfallAdapter
//
//  Copyright © 2023 Smaato. All rights reserved.
//

#import "SmaatoApplovinMediationAdapter.h"
#import <SmaatoSDKCore/SmaatoSDKCore.h>
#import <SmaatoSDKBanner/SmaatoSDKBanner.h>
#import <SmaatoSDKInterstitial/SmaatoSDKInterstitial.h>
#import <SmaatoSDKRewardedAds/SmaatoSDKRewardedAds.h>

static NSString *const kSmaatoApplovinMediationAdaptorVersion = @"13.0.0.0";
static MAAdapterInitializationStatus ALSmaatoInitializationStatus = NSIntegerMin;
/**
 * Router for interstitial/rewarded ad events.
 * Ads are removed on ad displayed/expired, as Smaato will allow a new ad load for the same adSpaceId.
 */

@interface SmaatoMediationAdapterRouter : ALMediationAdapterRouter <SMAInterstitialDelegate, SMARewardedInterstitialDelegate>
- (nullable SMAInterstitial *)interstitialAdForPlacementIdentifier:(NSString *)placementIdentifier;
- (nullable SMARewardedInterstitial *)rewardedAdForPlacementIdentifier:(NSString *)placementIdentifier;
@end

/**
 * Smaato banners are instance-based.
 */
@interface SmaatoApplovinMediationBannerAdDelegate : NSObject <SMABannerViewDelegate>
@property (nonatomic, weak) SmaatoApplovinMediationAdapter *smaatoWaterfallAdapter;
@property (nonatomic, strong) id<MAAdViewAdapterDelegate> delegate;
- (instancetype)initWithSmaatoWaterfallAdapter:(SmaatoApplovinMediationAdapter *)smaatoWaterfallAdapter andNotify:(id<MAAdViewAdapterDelegate>)delegate;
@end

@interface SmaatoApplovinMediationAdapter()

// BannerAdView Properties
@property (nonatomic, strong) SMABannerView *bannerAdView;
@property (nonatomic, strong) SmaatoApplovinMediationBannerAdDelegate *bannerAdViewAdapterDelegate;
// Interstitial
@property (nonatomic, strong) SMAInterstitial *interstitialAd;
// Rewarded
@property (nonatomic, strong) SMARewardedInterstitial *rewardedAd;
// Used by the mediation adapter router
@property (nonatomic, copy, nullable) NSString *placementIdentifier;
// Interstitial/Rewarded ad delegate router
@property (nonatomic, strong, readonly) SmaatoMediationAdapterRouter *router;



@end
@implementation SmaatoApplovinMediationAdapter
@dynamic router;

- (void)initializeWithParameters:(id<MAAdapterInitializationParameters>)parameters completionHandler:(void (^)(MAAdapterInitializationStatus, NSString *_Nullable))completionHandler {
    [self log: @"initializeWithParameters called"];
    static dispatch_once_t onceToken;
       dispatch_once(&onceToken, ^{
           
           NSString *pubID = [parameters.serverParameters al_stringForKey: @"pub_id" defaultValue: @""];
           [self log: @"Initializing Smaato SDK with publisher id: %@...", pubID];
                      
           // NOTE: This does not work atm
           [self updateLocationCollectionEnabled: parameters];
           
           SMAConfiguration *config = [[SMAConfiguration alloc] initWithPublisherId: pubID];
           config.logLevel = [parameters isTesting] ? kSMALogLevelVerbose : kSMALogLevelError;
           config.httpsOnly = [parameters.serverParameters al_numberForKey: @"https_only"].boolValue;
           
           [SmaatoSDK initSDKWithConfig: config];
       });
       
       completionHandler(MAAdapterInitializationStatusDoesNotApply, nil);
}

- (NSString *)SDKVersion
{
    return [SmaatoSDK sdkVersion];
}

- (NSString *)adapterVersion
{
    return kSmaatoApplovinMediationAdaptorVersion;
}


#pragma mark - Helper Methods

- (void)updateLocationCollectionEnabled:(id<MAAdapterParameters>)parameters
{
    if ( ALSdk.versionCode >= 11000000 )
    {
        NSDictionary<NSString *, id> *localExtraParameters = parameters.localExtraParameters;
        NSNumber *isLocationCollectionEnabled = [localExtraParameters al_numberForKey: @"is_location_collection_enabled"];
        if ( isLocationCollectionEnabled )
        {
            [self log: @"Setting location collection enabled: %@", isLocationCollectionEnabled];
            // NOTE: According to docs - this is disabled by default
            SmaatoSDK.gpsEnabled = isLocationCollectionEnabled.boolValue;
        }
    }
}

- (SMABannerAdSize)adSizeForAdFormat:(MAAdFormat *)adFormat
{
    if ( adFormat == MAAdFormat.banner )
    {
        return kSMABannerAdSizeXXLarge_320x50;
    }
    else if ( adFormat == MAAdFormat.mrec )
    {
        return kSMABannerAdSizeMediumRectangle_300x250;
    }
    else if ( adFormat == MAAdFormat.leader )
    {
        return kSMABannerAdSizeLeaderboard_728x90;
    }
    else
    {
        [NSException raise: NSInvalidArgumentException format: @"Unsupported ad format: %@", adFormat];
        return kSMABannerAdSizeAny;
    }
}

+ (MAAdapterError *)toMaxError:(NSError *)smaatoError
{
    NSInteger smaatoErrorCode = smaatoError.code;
    MAAdapterError *adapterError = MAAdapterError.unspecified;
    switch ( smaatoErrorCode )
    {
        case 1:
        case 204:
            adapterError = MAAdapterError.noFill;
            break;
        case 100:
            adapterError = MAAdapterError.noConnection;
            break;
        case 203:
            adapterError = MAAdapterError.invalidConfiguration;
            break;
        default:
            adapterError = MAAdapterError.unspecified;
    }
    return [MAAdapterError errorWithCode:adapterError.code errorString:adapterError.message mediatedNetworkErrorCode:smaatoErrorCode mediatedNetworkErrorMessage:smaatoError.localizedDescription];
}
#pragma mark - Dynamic Properties

- (SmaatoMediationAdapterRouter *)router
{
    return [SmaatoMediationAdapterRouter sharedInstance];
}

- (void)destroy
{
    self.bannerAdView.delegate = nil;
    self.bannerAdView = nil;
    self.bannerAdViewAdapterDelegate.delegate = nil;
    self.bannerAdViewAdapterDelegate = nil;
    self.interstitialAd = nil;
    self.rewardedAd = nil;
    [self.router removeAdapter: self forPlacementIdentifier: self.placementIdentifier];
}

#pragma mark - MAAdViewAdapter Methods

- (void)loadAdViewAdForParameters:(id<MAAdapterResponseParameters>)parameters adFormat:(MAAdFormat *)adFormat andNotify:(id<MAAdViewAdapterDelegate>)delegate
{
    [self log: @"Loading %@ ad view ad...", adFormat.label];
    
    NSString* placementIdentifier = [parameters thirdPartyAdPlacementIdentifier];
    [self updateLocationCollectionEnabled: parameters];
    
    self.bannerAdView = [[SMABannerView alloc] init];
    self.bannerAdView.autoreloadInterval = kSMABannerAutoreloadIntervalDisabled;
    
    self.bannerAdViewAdapterDelegate = [[SmaatoApplovinMediationBannerAdDelegate alloc] initWithSmaatoWaterfallAdapter:self andNotify:delegate];
    self.bannerAdView.delegate = self.bannerAdViewAdapterDelegate;
    
    if ( !placementIdentifier || ![placementIdentifier al_isValidString] )
    {
        [self log: @"%@ ad load failed: ad request nil with valid bid response", adFormat.label];
        [delegate didFailToLoadAdViewAdWithError: MAAdapterError.invalidConfiguration];
    }
    else
    {
        [self.bannerAdView loadWithAdSpaceId: placementIdentifier adSize: [self adSizeForAdFormat: adFormat]];
    }
}
#pragma mark - MAInterstitialAdapter Methods

- (void)loadInterstitialAdForParameters:(id<MAAdapterResponseParameters>)parameters andNotify:(id<MAInterstitialAdapterDelegate>)delegate
{
    self.placementIdentifier = parameters.thirdPartyAdPlacementIdentifier;
    [self updateLocationCollectionEnabled: parameters];
    [self.router addInterstitialAdapter: self
                               delegate: delegate
                 forPlacementIdentifier: self.placementIdentifier];
    
    if ( [[self.router interstitialAdForPlacementIdentifier: self.placementIdentifier] availableForPresentation] )
    {
        [self log: @"Interstitial ad already loaded for placement: %@...", self.placementIdentifier];
        [delegate didLoadInterstitialAd];
        
        return;
    }
    
    if ( !self.placementIdentifier || ![self.placementIdentifier al_isValidString])
    {
        [self log: @"Interstitial ad load failed: ad request nil"];
        [delegate didFailToLoadInterstitialAdWithError: MAAdapterError.invalidConfiguration];
    }
    else
    {
        [SmaatoSDK loadInterstitialForAdSpaceId: self.placementIdentifier delegate: self.router];
    }
}

- (void)showInterstitialAdForParameters:(id<MAAdapterResponseParameters>)parameters andNotify:(id<MAInterstitialAdapterDelegate>)delegate
{
    NSString *placementIdentifier = parameters.thirdPartyAdPlacementIdentifier;
    [self log: @"Showing interstitial ad for placement: %@...", placementIdentifier];
    [self.router addShowingAdapter: self];
    
    self.interstitialAd = [self.router interstitialAdForPlacementIdentifier: placementIdentifier];
    
    if ( [self.interstitialAd availableForPresentation] )
    {
        UIViewController *presentingViewController;
        if ( ALSdk.versionCode >= 11020199 )
        {
            presentingViewController = parameters.presentingViewController ?: [ALUtils topViewControllerFromKeyWindow];
        }
        else
        {
            presentingViewController = [ALUtils topViewControllerFromKeyWindow];
        }
        
        [self.interstitialAd showFromViewController: presentingViewController];
    }
    {
        [self log: @"Interstitial ad not ready"];
        [self.router didFailToDisplayAdForPlacementIdentifier: placementIdentifier error: [MAAdapterError errorWithCode: -4205
                                                                                                            errorString: @"Ad Display Failed"
                                                                                                 mediatedNetworkErrorCode:0 mediatedNetworkErrorMessage:@"Interstitial ad not ready"]];
    }
}
#pragma mark - MARewardedAdapter Methods

- (void)loadRewardedAdForParameters:(id<MAAdapterResponseParameters>)parameters andNotify:(id<MARewardedAdapterDelegate>)delegate
{
    self.placementIdentifier = parameters.thirdPartyAdPlacementIdentifier;
    
    [self updateLocationCollectionEnabled: parameters];
    [self.router addRewardedAdapter: self
                           delegate: delegate
             forPlacementIdentifier: self.placementIdentifier];
    
    if ( [[self.router rewardedAdForPlacementIdentifier: self.placementIdentifier] availableForPresentation] )
    {
        [self log: @"Rewarded ad already loaded for placement: %@...", self.placementIdentifier];
        [delegate didLoadRewardedAd];
        
        return;
    }
    if (!self.placementIdentifier || ![self.placementIdentifier al_isValidString])
    {
        [self log: @"Rewarded ad load failed: ad request nil"];
        [delegate didFailToLoadRewardedAdWithError: MAAdapterError.invalidConfiguration];
    }
    else
    {
        [SmaatoSDK loadRewardedInterstitialForAdSpaceId: self.placementIdentifier delegate: self.router];
    }
}
- (void)showRewardedAdForParameters:(id<MAAdapterResponseParameters>)parameters andNotify:(id<MARewardedAdapterDelegate>)delegate
{
    NSString *placementIdentifier = parameters.thirdPartyAdPlacementIdentifier;
    [self log: @"Showing rewarded ad for placement: %@...", placementIdentifier];
    [self.router addShowingAdapter: self];
    
    self.rewardedAd = [self.router rewardedAdForPlacementIdentifier: placementIdentifier];
    
    if ( [self.rewardedAd availableForPresentation] )
    {
        // Configure reward from server.
        [self configureRewardForParameters: parameters];
        
        UIViewController *presentingViewController;
        if ( ALSdk.versionCode >= 11020199 )
        {
            presentingViewController = parameters.presentingViewController ?: [ALUtils topViewControllerFromKeyWindow];
        }
        else
        {
            presentingViewController = [ALUtils topViewControllerFromKeyWindow];
        }
        
        [self.rewardedAd showFromViewController: presentingViewController];
    }
    else
    {
        [self log: @"Rewarded ad not ready"];
        [self.router didFailToDisplayAdForPlacementIdentifier: placementIdentifier error: [MAAdapterError errorWithCode: -4205
                                                                                                            errorString: @"Ad Display Failed"
                                                                                               mediatedNetworkErrorCode: 0
                                                                                            mediatedNetworkErrorMessage: @"Rewarded ad not ready"]];
    }
}
@end

#pragma mark - Smaato BannerAdView Delegate

@implementation SmaatoApplovinMediationBannerAdDelegate

- (instancetype)initWithSmaatoWaterfallAdapter:(SmaatoApplovinMediationAdapter *)smaatoWaterfallAdapter andNotify:(id<MAAdViewAdapterDelegate>)delegate
{
    self = [super init];
    if ( self )
    {
        self.smaatoWaterfallAdapter = smaatoWaterfallAdapter;
        self.delegate = delegate;
    }
    return self;
}

- (UIViewController *)presentingViewControllerForBannerView:(SMABannerView *)bannerView
{
    return [ALUtils topViewControllerFromKeyWindow];
}

- (void)bannerViewDidLoad:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView loaded"];
    
    // Passing extra info such as creative id supported in 6.15.0+
    if ( ALSdk.versionCode >= 6150000 && [bannerView.sci al_isValidString] )
    {
        [self.delegate performSelector: @selector(didLoadAdForAdView:withExtraInfo:)
                            withObject: bannerView
                            withObject: @{@"creative_id" : bannerView.sci}];
    }
    else
    {
        [self.delegate didLoadAdForAdView: bannerView];
    }
}

- (void)bannerView:(SMABannerView *)bannerView didFailWithError:(NSError *)error
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView failed to load with error: %@", error];
    
    MAAdapterError *adapterError = [SmaatoApplovinMediationAdapter toMaxError: error];
    [self.delegate didFailToLoadAdViewAdWithError: adapterError];
}

- (void)bannerViewDidTTLExpire:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView ad expired"];
}

- (void)bannerViewDidImpress:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView displayed"];
    [self.delegate didDisplayAdViewAd];
}

- (void)bannerViewDidClick:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView clicked"];
    [self.delegate didClickAdViewAd];
}

- (void)bannerViewDidPresentModalContent:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView expanded"];
    [self.delegate didExpandAdViewAd];
}

- (void)bannerViewDidDismissModalContent:(SMABannerView *)bannerView
{
    [self.smaatoWaterfallAdapter log: @"BannerAdView collapsed"];
    [self.delegate didCollapseAdViewAd];
}
@end

#pragma mark - Smaato Interstitial/Rewarded Router

@interface SmaatoMediationAdapterRouter ()
// Interstitial
@property (nonatomic, strong) NSMutableDictionary<NSString *, SMAInterstitial *> *interstitialAds;
@property (nonatomic, strong) NSObject *interstitialAdsLock;

// Rewarded
@property (nonatomic, strong) NSMutableDictionary<NSString *, SMARewardedInterstitial *> *rewardedAds;
@property (nonatomic, strong) NSObject *rewardedAdsLock;

@property (nonatomic, assign, getter=hasGrantedReward) BOOL grantedReward;
@end

@implementation SmaatoMediationAdapterRouter

- (instancetype)init
{
    self = [super init];
    if ( self )
    {
        self.interstitialAdsLock = [[NSObject alloc] init];
        self.interstitialAds = [NSMutableDictionary dictionary];
        
        self.rewardedAdsLock = [[NSObject alloc] init];
        self.rewardedAds = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable SMAInterstitial *)interstitialAdForPlacementIdentifier:(NSString *)placementIdentifier
{
    @synchronized ( self.interstitialAdsLock )
    {
        return self.interstitialAds[placementIdentifier];
    }
}

- (nullable SMARewardedInterstitial *)rewardedAdForPlacementIdentifier:(NSString *)placementIdentifier
{
    @synchronized ( self.rewardedAdsLock )
    {
        return self.rewardedAds[placementIdentifier];
    }
}

#pragma mark - Interstitial Delegate Methods

- (void)interstitialDidLoad:(SMAInterstitial *)interstitial
{
    NSString *placementIdentifier = interstitial.adSpaceId;
    
    @synchronized ( self.interstitialAdsLock )
    {
        self.interstitialAds[placementIdentifier] = interstitial;
    }
    
    [self log: @"Interstitial ad loaded for placement: %@...", placementIdentifier];
    [self didLoadAdForCreativeIdentifier: interstitial.sci placementIdentifier: placementIdentifier];
}

- (void)interstitial:(nullable SMAInterstitial *)interstitial didFailWithError:(NSError *)error
{
    NSString *placementIdentifier = interstitial.adSpaceId;
    
    [self log: @"Interstitial ad failed to load for placement: %@...with error: %@", placementIdentifier, error];
    
    MAAdapterError *adapterError = [SmaatoApplovinMediationAdapter toMaxError: error];
    [self didFailToLoadAdForPlacementIdentifier: placementIdentifier error: adapterError];
}

- (void)interstitialDidTTLExpire:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad expired"];
    
    @synchronized ( self.interstitialAdsLock )
    {
        [self.interstitialAds removeObjectForKey: interstitial.adSpaceId];
    }
}

- (void)interstitialWillAppear:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad will appear"];
}

- (void)interstitialDidAppear:(SMAInterstitial *)interstitial
{
    // Allow the next interstitial to load
    @synchronized ( self.interstitialAdsLock )
    {
        [self.interstitialAds removeObjectForKey: interstitial.adSpaceId];
    }
    
    [self log: @"Interstitial ad displayed"];
    [self didDisplayAdForPlacementIdentifier: interstitial.adSpaceId];
}

- (void)interstitialDidClick:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad clicked"];
    [self didClickAdForPlacementIdentifier: interstitial.adSpaceId];
}

- (void)interstitialWillLeaveApplication:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad will leave application"];
}

- (void)interstitialWillDisappear:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad will disappear"];
}

- (void)interstitialDidDisappear:(SMAInterstitial *)interstitial
{
    [self log: @"Interstitial ad hidden"];
    [self didHideAdForPlacementIdentifier: interstitial.adSpaceId];
}

#pragma mark - Rewarded Delegate Methods

- (void)rewardedInterstitialDidLoad:(SMARewardedInterstitial *)rewardedInterstitial
{
    NSString *placementIdentifier = rewardedInterstitial.adSpaceId;
    
    @synchronized ( self.rewardedAdsLock )
    {
        self.rewardedAds[placementIdentifier] = rewardedInterstitial;
    }
    
    [self log: @"Rewarded ad loaded for placement: %@...", placementIdentifier];
    [self didLoadAdForCreativeIdentifier: rewardedInterstitial.sci placementIdentifier: placementIdentifier];
}

- (void)rewardedInterstitialDidFail:(nullable SMARewardedInterstitial *)rewardedInterstitial withError:(NSError *)error
{
    NSString *placementIdentifier = rewardedInterstitial.adSpaceId;
    
    [self log: @"Rewarded ad failed to load for placement: %@...with error: %@", placementIdentifier, error];
    
    MAAdapterError *adapterError = [SmaatoApplovinMediationAdapter toMaxError: error];
    [self didFailToLoadAdForPlacementIdentifier: placementIdentifier error: adapterError];
}

- (void)rewardedInterstitialDidTTLExpire:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad expired"];
    
    @synchronized ( self.rewardedAdsLock )
    {
        [self.rewardedAds removeObjectForKey: rewardedInterstitial.adSpaceId];
    }
}

- (void)rewardedInterstitialWillAppear:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad will appear"];
}

- (void)rewardedInterstitialDidAppear:(SMARewardedInterstitial *)rewardedInterstitial
{
    // Allow the next rewarded ad to load
    @synchronized ( self.rewardedAdsLock )
    {
        [self.rewardedAds removeObjectForKey: rewardedInterstitial.adSpaceId];
    }
    
    [self log: @"Rewarded ad displayed"];
}

- (void)rewardedInterstitialDidStart:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Reward ad video started"];
    [self didDisplayAdForPlacementIdentifier: rewardedInterstitial.adSpaceId];
}

- (void)rewardedInterstitialDidClick:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad clicked"];
    [self didClickAdForPlacementIdentifier: rewardedInterstitial.adSpaceId];
}

- (void)rewardedInterstitialWillLeaveApplication:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad will leave application"];
}

- (void)rewardedInterstitialDidReward:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad video completed"];
    self.grantedReward = YES;
    NSString *placementIdentifier = rewardedInterstitial.adSpaceId;
    
    if ( [self hasGrantedReward] || [self shouldAlwaysRewardUserForPlacementIdentifier: placementIdentifier] )
    {
        MAReward *reward = [self rewardForPlacementIdentifier: placementIdentifier];
        [self log: @"Rewarded user with reward: %@", reward];
        [self didRewardUserForPlacementIdentifier: placementIdentifier withReward: reward];
    }
}

- (void)rewardedInterstitialWillDisappear:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad will disappear"];
}

- (void)rewardedInterstitialDidDisappear:(SMARewardedInterstitial *)rewardedInterstitial
{
    [self log: @"Rewarded ad hidden"];
    NSString *placementIdentifier = rewardedInterstitial.adSpaceId;
    [self didHideAdForPlacementIdentifier: placementIdentifier];
}

#pragma mark - Utility Methods

- (void)didLoadAdForCreativeIdentifier:(nullable NSString *)creativeIdentifier placementIdentifier:(NSString *)placementIdentifier
{
    // Passing extra info such as creative id supported in 6.15.0+
    if ( ALSdk.versionCode >= 6150000 && [creativeIdentifier al_isValidString] )
    {
        [self performSelector: @selector(didLoadAdForPlacementIdentifier:withExtraInfo:)
                   withObject: placementIdentifier
                   withObject: @{@"creative_id" : creativeIdentifier}];
    }
    else
    {
        [self didLoadAdForPlacementIdentifier: placementIdentifier];
    }
}

@end





