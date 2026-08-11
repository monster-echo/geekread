import { RuntimeConfig } from '../domain/Models'
import { AppRoute } from './AppRoute'

export class RouteDecision {
  route: AppRoute
  pending: AppRoute | null
  unavailable: boolean

  constructor(route: AppRoute, pending: AppRoute | null = null, unavailable: boolean = false) {
    this.route = route
    this.pending = pending
    this.unavailable = unavailable
  }
}

export function guardRoute(
  route: AppRoute,
  signedIn: boolean,
  config: RuntimeConfig | null
): RouteDecision {
  if (requiresAuthentication(route) && !signedIn) {
    return new RouteDecision(AppRoute.SignIn, route)
  }
  if (!featureAllows(route, config)) {
    return new RouteDecision(AppRoute.Home, null, true)
  }
  return new RouteDecision(route)
}

function requiresAuthentication(route: AppRoute): boolean {
  return route === AppRoute.ProfileEdit || route === AppRoute.Statistics ||
    route === AppRoute.Invite || route === AppRoute.Coupons ||
    route === AppRoute.Checkout || route === AppRoute.Orders ||
    route === AppRoute.AccountSecurity || route === AppRoute.Devices ||
    route === AppRoute.DeleteAccount || route === AppRoute.NotificationCenter ||
    route === AppRoute.SupportTicket || route === AppRoute.NewSupportTicket ||
    route === AppRoute.ProductFeedback
}

function featureAllows(route: AppRoute, config: RuntimeConfig | null): boolean {
  const features = config?.features ?? {}
  if (route === AppRoute.Membership || route === AppRoute.MembershipPlans ||
    route === AppRoute.Checkout || route === AppRoute.Orders) {
    return features['membership'] === true
  }
  if (route === AppRoute.NotificationCenter) return features['notifications'] === true
  if (route === AppRoute.ProfileEdit) return features['profileEditing'] === true
  if (route === AppRoute.Statistics) return features['statistics'] === true
  if (route === AppRoute.Coupons) return features['coupons'] === true
  if (route === AppRoute.Invite) return features['invites'] === true
  if (route === AppRoute.DeleteAccount) return features['accountDeletion'] === true
  if (route === AppRoute.HelpFeedback || route === AppRoute.SupportTicket ||
    route === AppRoute.NewSupportTicket || route === AppRoute.ProductFeedback) {
    return config?.support.enabled === true
  }
  return true
}
