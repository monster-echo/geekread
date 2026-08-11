import React from 'react';
import { FeedbackHost } from '../design-system/FeedbackHost';
import { useApp } from '../state/AppStore';
import { AuthScreen } from '../screens/AuthScreens';
import { HomeScreen } from '../screens/HomeScreen';
import { OnboardingScreen, SplashScreen } from '../screens/LaunchScreens';
import {
  EditProfileScreen,
  ProfileScreen,
} from '../screens/ProfileScreens';
import { MembershipScreen } from '../screens/MembershipScreen';
import { CheckoutScreen } from '../screens/CheckoutScreen';
import { CouponsScreen, InviteScreen, StatisticsScreen } from '../screens/ProfileUtilityScreens';
import {
  AccountSecurityScreen,
  DevicesScreen,
  SettingsScreen,
} from '../screens/SettingsScreens';
import { DeleteAccountScreen, PreferenceScreen } from '../screens/SettingsPreferenceScreens';
import {
  LegalIndexScreen,
  PrivacyPolicyScreen,
  SubscriptionTermsScreen,
  TermsOfServiceScreen,
} from '../screens/LegalScreens';
import { StateGalleryScreen } from '../screens/StateGalleryScreen';
import { AboutScreen, NotificationsScreen, OrdersScreen } from '../screens/DataScreens';
import { SupportHomeScreen, TicketDetailScreen } from '../screens/SupportScreens';
import { NewTicketScreen, ProductFeedbackScreen } from '../screens/SupportFormScreens';
import {
  PermissionsScreen,
  StorageScreen,
  TextSizeScreen,
} from '../screens/SettingsUtilityScreens';

const titles: Readonly<Record<string, string>> = {
  'profile.edit': '个人资料',
  'profile.statistics': '使用统计',
  'profile.invite': '邀请好友',
  'profile.coupons': '优惠券',
  'membership.plans': '方案对比',
  'membership.checkout': '订阅确认',
  'membership.orders': '订单管理',
  'notifications.center': '通知中心',
  'settings.accountSecurity': '账户与安全',
  'settings.devices': '登录设备管理',
  'settings.notifications': '通知设置',
  'settings.privacy': '隐私设置',
  'settings.general': '通用设置',
  'settings.appearance': '外观主题',
  'settings.language': '语言',
  'settings.textSize': '字体大小',
  'settings.storage': '存储与缓存',
  'settings.permissions': '权限管理',
  'settings.helpFeedback': '帮助与反馈',
  'settings.legal': '协议与政策',
  'settings.about': '关于与版本',
};

export function AppRouter() {
  const { route } = useApp();
  let screen: React.ReactNode;
  switch (route) {
    case 'launch.splash': screen = <SplashScreen />; break;
    case 'launch.onboarding': screen = <OnboardingScreen />; break;
    case 'home': screen = <HomeScreen />; break;
    case 'auth.signIn': screen = <AuthScreen mode="signIn" />; break;
    case 'auth.signUp': screen = <AuthScreen mode="signUp" />; break;
    case 'auth.phone': screen = <AuthScreen mode="phone" />; break;
    case 'auth.forgotPassword': screen = <AuthScreen mode="forgot" />; break;
    case 'auth.verifyEmail': screen = <AuthScreen mode="verify" />; break;
    case 'auth.resetPassword': screen = <AuthScreen mode="reset" />; break;
    case 'profile.home': screen = <ProfileScreen />; break;
    case 'profile.edit': screen = <EditProfileScreen />; break;
    case 'profile.statistics': screen = <StatisticsScreen />; break;
    case 'profile.invite': screen = <InviteScreen />; break;
    case 'profile.coupons': screen = <CouponsScreen />; break;
    case 'membership.home': screen = <MembershipScreen />; break;
    case 'membership.plans': screen = <MembershipScreen />; break;
    case 'membership.checkout': screen = <CheckoutScreen />; break;
    case 'membership.orders': screen = <OrdersScreen />; break;
    case 'notifications.center': screen = <NotificationsScreen />; break;
    case 'settings.home': screen = <SettingsScreen />; break;
    case 'settings.accountSecurity': screen = <AccountSecurityScreen />; break;
    case 'settings.devices': screen = <DevicesScreen />; break;
    case 'settings.notifications':
      screen = <PreferenceScreen kind="notifications" title="通知设置" />; break;
    case 'settings.general':
      screen = <PreferenceScreen kind="general" title="通用设置" />; break;
    case 'settings.privacy':
      screen = <PreferenceScreen kind="privacy" title="隐私设置" />; break;
    case 'settings.appearance':
      screen = <PreferenceScreen kind="appearance" title="外观主题" />; break;
    case 'settings.language':
      screen = <PreferenceScreen kind="language" title="语言" />; break;
    case 'settings.textSize': screen = <TextSizeScreen />; break;
    case 'settings.storage': screen = <StorageScreen />; break;
    case 'settings.permissions': screen = <PermissionsScreen />; break;
    case 'settings.legal': screen = <LegalIndexScreen />; break;
    case 'settings.privacyPolicy': screen = <PrivacyPolicyScreen />; break;
    case 'settings.termsOfService': screen = <TermsOfServiceScreen />; break;
    case 'settings.subscriptionTerms': screen = <SubscriptionTermsScreen />; break;
    case 'settings.helpFeedback': screen = <SupportHomeScreen />; break;
    case 'support.newTicket': screen = <NewTicketScreen />; break;
    case 'support.ticket': screen = <TicketDetailScreen />; break;
    case 'support.feedback': screen = <ProductFeedbackScreen />; break;
    case 'settings.about': screen = <AboutScreen />; break;
    case 'settings.deleteAccount': screen = <DeleteAccountScreen />; break;
    case 'states.gallery': screen = <StateGalleryScreen />; break;
    default: screen = <HomeScreen />;
  }
  return (
    <>
      {screen}
      <FeedbackHost />
    </>
  );
}
